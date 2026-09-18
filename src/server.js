'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const express = require('express');

const db = require('./db');
const { PATHS } = require('./paths');
const { USER_AGENT } = require('./scraper/browser');
const { loadCookies, hasSessionCookie, hasClearance } = require('./scraper/session');
const { imageStats } = require('./scraper/images');

const PORT = Number(process.env.PORT || 5180);
const PUBLIC_DIR = path.join(__dirname, 'public');

const app = express();
app.use(express.json({ limit: '1mb' }));

// 本地前端资源不做任何缓存，避免改完代码后浏览器还在跑旧版本
app.use(
  express.static(PUBLIC_DIR, {
    extensions: ['html'],
    etag: false,
    lastModified: false,
    cacheControl: true,
    maxAge: 0,
    setHeaders: (res) => {
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');
    },
  }),
);

// 本地缓存的下厨房图片
app.use('/images', express.static(PATHS.IMAGE_DIR, { maxAge: '1d', fallthrough: true }));

/* ------------------------------------------------------------------ */
/* 菜谱查询                                                             */
/* ------------------------------------------------------------------ */

app.get('/api/recipes', (req, res) => {
  const { q = '', tag = '', sort = 'collected', order = 'desc', page = 1, pageSize = 24 } = req.query;
  try {
    const result = db.queryRecipes({
      q: String(q),
      tag: String(tag),
      sort: String(sort),
      order: String(order),
      page: Number(page),
      pageSize: Number(pageSize),
    });
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/recipes/:id', (req, res) => {
  const recipe = db.getRecipe(req.params.id);
  if (!recipe) return res.status(404).json({ error: '菜谱不存在' });
  res.json(recipe);
});

app.delete('/api/recipes/:id', (req, res) => {
  const { ok, images } = db.deleteRecipeWithImages(req.params.id);
  let deleted = 0;
  let missing = 0;
  for (const publicPath of images) {
    if (typeof publicPath !== 'string' || !publicPath.startsWith('/images/')) continue;
    const fp = path.join(PATHS.IMAGE_DIR, publicPath.replace(/^\/images\//, ''));
    try {
      fs.unlinkSync(fp);
      deleted += 1;
    } catch (error) {
      if (error && error.code === 'ENOENT') missing += 1;
      else console.warn('删除图片失败', fp, error && error.message);
    }
  }
  res.json({ ok, deletedImages: deleted, missingImages: missing });
});

app.post('/api/recipes/:id/touch', (req, res) => {
  const ok = db.touchRecipe(req.params.id);
  if (!ok) return res.status(404).json({ error: '菜谱不存在' });
  res.json({ ok: true, updatedAt: new Date().toISOString() });
});

app.get('/api/tags', (req, res) => {
  res.json(db.getTags(Number(req.query.limit || 80)));
});

app.get('/api/stats', (req, res) => {
  res.json({ ...db.getStats(), images: imageStats() });
});

app.get('/api/session', (req, res) => {
  const saved = loadCookies();
  res.json({
    saved: Boolean(saved),
    savedAt: saved ? saved.savedAt : null,
    cookieCount: saved ? saved.cookies.length : 0,
    hasSession: saved ? hasSessionCookie(saved.cookies) : false,
    hasClearance: saved ? hasClearance(saved.cookies) : false,
  });
});

/* ------------------------------------------------------------------ */
/* 图片代理（下厨房图床有防盗链）                                        */
/* ------------------------------------------------------------------ */

const imageCache = new Map();
const IMAGE_CACHE_MAX = 300;

app.get('/api/image', async (req, res) => {
  const target = String(req.query.url || '');
  if (!/^https?:\/\//i.test(target)) return res.status(400).end();

  let parsed;
  try {
    parsed = new URL(target);
  } catch {
    return res.status(400).end();
  }
  if (!/(^|\.)(chuimg\.com|xiachufang\.com)$/i.test(parsed.hostname)) {
    return res.status(403).end();
  }

  const cached = imageCache.get(target);
  if (cached) {
    res.set({ 'Content-Type': cached.type, 'Cache-Control': 'public, max-age=604800' });
    return res.end(cached.buffer);
  }

  try {
    const upstream = await fetch(target, {
      headers: {
        Referer: 'https://www.xiachufang.com/',
        'User-Agent': USER_AGENT,
        Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      },
    });
    if (!upstream.ok) return res.status(upstream.status).end();

    const buffer = Buffer.from(await upstream.arrayBuffer());
    const type = upstream.headers.get('content-type') || 'image/jpeg';

    if (imageCache.size >= IMAGE_CACHE_MAX) {
      imageCache.delete(imageCache.keys().next().value);
    }
    imageCache.set(target, { buffer, type });

    res.set({ 'Content-Type': type, 'Cache-Control': 'public, max-age=604800' });
    res.end(buffer);
  } catch {
    res.status(502).end();
  }
});

/* ------------------------------------------------------------------ */
/* 抓取任务                                                             */
/* ------------------------------------------------------------------ */

const SCRIPTS = {
  login: 'login.js',
  scrape: 'scrape.js',
  images: 'fetch-images.js',
};

const listeners = new Set();
const MAX_LOG_LINES = 500;

let currentJob = null;

function publicJob() {
  if (!currentJob) return null;
  const { child, logs, ...rest } = currentJob;
  return { ...rest, logLines: logs.length };
}

function broadcast(event) {
  const payload = `data: ${JSON.stringify(event)}\n\n`;
  for (const res of listeners) {
    try {
      res.write(payload);
    } catch {
      listeners.delete(res);
    }
  }
}

function pushLog(line) {
  if (!currentJob) return;
  currentJob.logs.push(line);
  if (currentJob.logs.length > MAX_LOG_LINES) currentJob.logs.splice(0, currentJob.logs.length - MAX_LOG_LINES);
  broadcast({ type: 'log', message: line });
}

function isRunning() {
  return Boolean(currentJob && currentJob.status === 'running');
}

function startJob(kind, scriptArgs) {
  if (isRunning()) {
    const error = new Error('已有任务正在运行，请等待其结束');
    error.statusCode = 409;
    throw error;
  }

  const scriptPath = path.join(__dirname, 'scraper', SCRIPTS[kind] || 'scrape.js');

  currentJob = {
    id: `${kind}-${Date.now()}`,
    kind,
    status: 'running',
    startedAt: new Date().toISOString(),
    finishedAt: null,
    exitCode: null,
    args: scriptArgs,
    progress: null,
    logs: [],
  };

  const child = spawn(process.execPath, ['--no-warnings', scriptPath, ...scriptArgs], {
    cwd: PATHS.ROOT_DIR,
    env: process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: false,
  });
  currentJob.child = child;

  let buffer = '';
  const handleChunk = (chunk) => {
    buffer += chunk.toString('utf8');
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const rawLine of lines) {
      const line = rawLine.trimEnd();
      if (!line) continue;
      if (line.startsWith('@@EVENT ')) {
        try {
          const event = JSON.parse(line.slice(8));
          if (event.type === 'start' || event.type === 'page' || event.type === 'collected' || event.type === 'recipe') {
            currentJob.progress = event;
          }
          if (event.type === 'done') currentJob.progress = { type: 'done', ...event };
          broadcast(event);
        } catch {
          pushLog(line);
        }
      } else {
        pushLog(line);
      }
    }
  };

  child.stdout.on('data', handleChunk);
  child.stderr.on('data', handleChunk);

  child.on('close', (code) => {
    if (buffer.trim()) pushLog(buffer.trim());
    currentJob.status = code === 0 ? 'done' : 'failed';
    currentJob.exitCode = code;
    currentJob.finishedAt = new Date().toISOString();
    broadcast({ type: 'job-finished', status: currentJob.status, exitCode: code, kind });
    pushLog(`[任务结束] ${kind} 退出码 ${code}`);
  });

  child.on('error', (error) => {
    currentJob.status = 'failed';
    currentJob.exitCode = -1;
    pushLog(`[任务错误] ${error.message}`);
    broadcast({ type: 'error', message: error.message });
  });

  broadcast({ type: 'job-started', job: publicJob() });
  return publicJob();
}

app.post('/api/jobs/login', (req, res) => {
  try {
    const job = startJob('login', ['--timeout', String(Number(req.body?.timeout || 600))]);
    res.json({ ok: true, job });
  } catch (error) {
    res.status(error.statusCode || 500).json({ error: error.message });
  }
});

app.post('/api/jobs/scrape', (req, res) => {
  const body = req.body || {};
  const args = [];
  // 菜谱 ID / URL 列表（换行/逗号/空格分隔）
  if (body.ids) args.push('--ids', String(body.ids));
  if (body.force) args.push('--force');
  if (body.debug) args.push('--debug');
  if (body.delay) args.push('--delay', String(Number(body.delay)));
  if (body.noImages) args.push('--no-images');
  if (body.imageSize != null && body.imageSize !== '') {
    args.push('--image-size', String(Number(body.imageSize)));
  }

  try {
    const job = startJob('scrape', args);
    res.json({ ok: true, job, args });
  } catch (error) {
    res.status(error.statusCode || 500).json({ error: error.message });
  }
});

app.post('/api/jobs/images', (req, res) => {
  const size = req.body?.size;
  const args = [];
  if (size != null && size !== '') args.push('--size', String(Number(size)));

  try {
    const job = startJob('images', args);
    res.json({ ok: true, job, args });
  } catch (error) {
    res.status(error.statusCode || 500).json({ error: error.message });
  }
});

app.post('/api/jobs/cancel', (req, res) => {
  if (!isRunning()) return res.json({ ok: false, message: '当前没有运行中的任务' });
  const child = currentJob.child;
  if (process.platform === 'win32') {
    spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true });
  } else {
    child.kill('SIGTERM');
  }
  pushLog('[任务取消] 已发送终止信号');
  res.json({ ok: true });
});

app.get('/api/jobs/current', (req, res) => {
  res.json({ job: publicJob(), logs: currentJob ? currentJob.logs.slice(-200) : [] });
});

app.get('/api/jobs/stream', (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders();

  res.write(
    `data: ${JSON.stringify({
      type: 'snapshot',
      job: publicJob(),
      logs: currentJob ? currentJob.logs.slice(-200) : [],
    })}\n\n`,
  );

  listeners.add(res);
  const ping = setInterval(() => {
    try {
      res.write(': ping\n\n');
    } catch {
      /* ignore */
    }
  }, 15000);

  req.on('close', () => {
    clearInterval(ping);
    listeners.delete(res);
  });
});

/* ------------------------------------------------------------------ */

app.use((req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'Not Found' });
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

// 上次进程被杀掉时可能残留 status=running 的记录，启动时标记为已中止
db.db
  .prepare(`UPDATE scrape_runs SET status = 'aborted', finished_at = ? WHERE status = 'running'`)
  .run(new Date().toISOString());

app.listen(PORT, () => {
  const stats = db.getStats();
  process.stdout.write(
    `\n  菜谱库已启动\n  地址：http://localhost:${PORT}\n  本地菜谱数量：${stats.total}\n\n`,
  );
});
