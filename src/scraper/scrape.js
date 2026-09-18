'use strict';

/**
 * 半自动抓取流程：
 *   1. 读取 data/cookies.json 中的登录态；没有、失效或触发风控 → 弹出浏览器让你手动处理；
 *   2. 逐个抓取用户给定的菜谱详情页，解析名称 / 用料 / 步骤 / 小贴士等；
 *   3. 写入本地 SQLite（默认跳过已存在的菜谱，加 --force 可覆盖更新）。
 *
 * 用法：
 *   node --no-warnings src/scraper/scrape.js --ids "123456
 *   107691482"
 *   node --no-warnings src/scraper/scrape.js --force
 *
 * 参数：
 *   --ids <text>      菜谱 ID / URL 列表，换行/逗号/空格分隔
 *   --force           强制更新已存在的菜谱
 *   --debug           解析异常时把 HTML 写到 data/debug/
 *   --delay <ms>      单次请求间隔毫秒数（默认 1200）
 *   --no-images       不下载图片，只保留远程地址
 *   --image-size <px> 图片最长边，0 = 原图（默认 1000）
 *   --wait-login <s>  等待人工登录 / 校验的秒数（默认 600）
 *   --dry-run         只解析不写库
 */

const fs = require('node:fs');
const path = require('node:path');

const db = require('../db');
const { PATHS, ensureDirs } = require('../paths');
const { SiteClient, CODES, loadCookies, saveCookies, sleep } = require('./session');
const { runLoginFlow } = require('./login');
const { HtmlParser } = require('./dom');
const { extractRecipeInPage } = require('./parse');
const { localizeRecipeImages } = require('./images');

const EVENT_PREFIX = '@@EVENT ';

/* ------------------------------------------------------------------ */
/* 输出                                                                */
/* ------------------------------------------------------------------ */

function emit(event) {
  process.stdout.write(`${EVENT_PREFIX}${JSON.stringify(event)}\n`);
}

function log(message) {
  process.stdout.write(`[SCRAPE] ${message}\n`);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) {
      args[key] = next;
      i += 1;
    } else {
      args[key] = true;
    }
  }
  return args;
}

/**
 * 从用户输入里提取菜谱 ID。
 * 接受的形式：
 *   - 纯数字 ID：        123456
 *   - 完整 URL：         https://www.xiachufang.com/recipe/123456/
 *   - 短链：             https://xiachufang.com/recipe/123456
 * 输入可用换行、逗号或空白分隔；返回去重后的 ID 列表（保持原顺序）。
 */
function parseRecipeInputs(input) {
  const seen = new Set();
  const ids = [];
  const text = String(input || '').replace(/\r/g, '');
  if (!text.trim()) return ids;
  for (const raw of text.split(/[\s,]+/)) {
    const token = raw.trim();
    if (!token) continue;
    const m = token.match(/\/recipe\/(\d+)/);
    const id = m ? m[1] : token;
    if (/^\d+$/.test(id) && !seen.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  }
  return ids;
}

/* ------------------------------------------------------------------ */
/* 会话                                                                */
/* ------------------------------------------------------------------ */

/**
 * 确保有一个可访问菜谱页的会话；必要时弹出浏览器让人工登录 / 过验证。
 */
async function ensureSession(client, probeUrl, waitLoginSec, { maxAttempts = 3 } = {}) {
  // 浏览器里过了校验、但 HTTP 请求仍被拦的次数
  let browserOkButHttpBlocked = 0;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const probe = await client.probe(probeUrl);
    if (probe.ok) {
      saveCookies(client.exportCookies());
      if (attempt === 1) log('登录态有效，开始抓取。');
      else log('会话已恢复，继续抓取。');
      return true;
    }

    log(`无法访问菜谱页：${probe.message}（${probe.code}）`);
    if (probe.code === CODES.CHALLENGE) {
      log('下厨房要求人机校验，接下来会打开浏览器，请拖动滑块完成验证。');
    } else if (probe.code === CODES.NOT_FOUND) {
      // 站点对未通过校验的请求，有时不重定向到验证页，而是直接返回 404 来伪装
      log('注意：如果确认这个菜谱存在，那这个 404 多半是人机校验在伪装。');
    }

    // 已经在浏览器里过了一次校验却还是被拦，说明不是人工操作的问题，
    // 再弹一次窗口只会让人困惑，直接停下来报告
    if (browserOkButHttpBlocked >= 2) {
      log('浏览器侧已通过校验，但脚本的 HTTP 请求仍被拦截，已停止重试。');
      log('建议：把请求间隔调大（如 --delay 2500）后稍等几分钟再试。');
      return false;
    }

    emit({ type: 'login-required', reason: probe.code, timeout: waitLoginSec });

    const result = await runLoginFlow({
      // 直接打开菜谱页，站点会自行把我们带到验证页 / 登录页
      url: probeUrl,
      probeUrl,
      requireLogin: false,
      timeoutSec: waitLoginSec,
      onEvent: (event) => (event.type === 'log' ? log(event.message) : emit(event)),
    });

    if (!result.ok) return false;
    browserOkButHttpBlocked += 1;
    client.setCookies(result.cookies);
  }

  log('多次尝试后仍无法访问菜谱页，请稍后重试。');
  return false;
}

/* ------------------------------------------------------------------ */
/* 单个菜谱                                                            */
/* ------------------------------------------------------------------ */

function normalizeRecipe(raw, sourceUrl) {
  const now = new Date().toISOString();
  return {
    id: String(raw.id || ''),
    url: raw.url || '',
    title: raw.title || '',
    description: raw.description || '',
    coverImage: raw.coverImage || '',
    author: raw.author || '',
    servings: raw.servings || '',
    ingredients: (raw.ingredients || []).filter((item) => item && item.name),
    steps: (raw.steps || []).filter((item) => item && (item.text || item.image)),
    tips: raw.tips || '',
    tags: raw.tags || [],
    madeCount: raw.madeCount || '',
    favCount: raw.favCount || '',
    sourceUrl,
    collectedAt: now,
  };
}

async function fetchRecipe(client, parser, id, { debug }) {
  const url = `https://www.xiachufang.com/recipe/${id}/`;
  const page = await client.fetchHtml(url);
  const raw = await parser.run(page.html, page.finalUrl, extractRecipeInPage, {
    pageUrl: page.finalUrl,
  });

  if (debug && (!raw || !raw.title || !raw.ingredients.length || !raw.steps.length)) {
    ensureDirs();
    fs.writeFileSync(path.join(PATHS.DEBUG_DIR, `${id}.html`), page.html, 'utf8');
    log(`解析不完整，已保存调试 HTML：data/debug/${id}.html`);
  }

  return raw;
}

/* ------------------------------------------------------------------ */
/* 主流程                                                              */
/* ------------------------------------------------------------------ */

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const force = Boolean(args.force);
  const debug = Boolean(args.debug);
  const delayMs = Number(args.delay || 1200);
  const waitLogin = Number(args['wait-login'] || 600);
  const dryRun = Boolean(args['dry-run']);
  const withImages = !args['no-images'];
  const imageSize = args['image-size'] != null ? Number(args['image-size']) : 1000;
  // 兼容旧调用：--only 也接受
  const ids = parseRecipeInputs(args.ids || args.input || args.only || '');

  if (!ids.length) {
    log('未提供任何菜谱 ID 或 URL，请在「抓取菜谱」弹窗里输入。');
    process.exitCode = 2;
    return;
  }

  log(`模式：${force ? '强制更新' : '增量跳过已有'}｜请求间隔 ${delayMs}ms`);
  log(
    withImages
      ? `图片：下载到本地 data/images（最长边 ${imageSize || '原图'}px）`
      : '图片：仅记录远程地址（--no-images）',
  );
  log(`目标：${ids.length} 个菜谱`);
  for (const id of ids) log(`  · ${id}`);

  const sourceUrl = `https://www.xiachufang.com/recipe/${ids[0]}/`;
  const runId = dryRun ? null : db.startScrapeRun(sourceUrl);
  const stats = {
    total: ids.length,
    added: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
    warnings: 0,
    images: 0,
  };

  emit({ type: 'start', sourceUrl, runId, force, ids });

  const client = new SiteClient({ delayMs });
  const saved = loadCookies();
  if (saved) {
    client.setCookies(saved.cookies);
    log(`已载入本地登录态（保存于 ${saved.savedAt}）。`);
  }

  let parser = null;
  let ok = false;

  try {
    if (!(await ensureSession(client, sourceUrl, waitLogin))) {
      emit({ type: 'error', message: CODES.LOGIN_REQUIRED, detail: '登录未完成，抓取已中止' });
      if (runId) db.finishScrapeRun(runId, { ...stats, status: 'failed', message: '登录未完成' });
      process.exitCode = 2;
      return;
    }

    log('正在启动解析引擎…');
    parser = await HtmlParser.create({ headless: true });

    emit({ type: 'collected', total: ids.length, planned: ids.length });

    let index = 0;
    for (const id of ids) {
      index += 1;
      const url = `https://www.xiachufang.com/recipe/${id}/`;

      if (!force && db.hasRecipe(id)) {
        stats.skipped += 1;
        emit({ type: 'recipe', index, total: ids.length, id, status: 'skipped' });
        log(`(${index}/${ids.length}) 跳过 ${id}（已存在）`);
        continue;
      }

      let attempt = 0;
      let settled = false;

      while (!settled && attempt < 2) {
        attempt += 1;
        try {
          const raw = await fetchRecipe(client, parser, id, { debug });
          const recipe = normalizeRecipe({ ...raw, id }, url);
          if (!recipe.title) throw new Error('未能解析出菜谱名称');

          const warnings = [...(raw.warnings || [])];

          let imageCount = 0;
          if (withImages) {
            const imageResult = await localizeRecipeImages(recipe, { size: imageSize });
            imageCount = imageResult.downloaded;
            stats.images += imageResult.downloaded;
            warnings.push(...imageResult.warnings);
          }

          if (dryRun) {
            stats.added += 1;
          } else if (db.upsertRecipe(recipe) === 'added') {
            stats.added += 1;
          } else {
            stats.updated += 1;
          }

          if (warnings.length) stats.warnings += 1;

          log(
            `(${index}/${ids.length}) ${recipe.title} ｜用料 ${recipe.ingredients.length} ｜步骤 ${recipe.steps.length}` +
              (withImages ? ` ｜图片 ${imageCount}` : '') +
              (warnings.length ? ` ｜⚠ ${warnings.join(',')}` : ''),
          );
          emit({
            type: 'recipe',
            index,
            total: ids.length,
            id,
            title: recipe.title,
            status: 'ok',
            ingredients: recipe.ingredients.length,
            steps: recipe.steps.length,
            images: imageCount,
            warnings,
          });
          settled = true;
        } catch (error) {
          const recoverable = error.code === CODES.CHALLENGE || error.code === CODES.LOGIN_REQUIRED;

          if (recoverable && attempt < 2) {
            log(`触发风控（${error.message}），尝试重新建立会话…`);
            if (await ensureSession(client, url, waitLogin, { maxAttempts: 2 })) continue;
          }

          stats.failed += 1;
          log(`(${index}/${ids.length}) 失败 ${id}：${error.message}`);
          emit({
            type: 'recipe',
            index,
            total: ids.length,
            id,
            status: 'failed',
            message: error.message,
          });
          settled = true;

          if (recoverable) {
            log('会话无法恢复，本轮抓取提前结束。');
            settled = true;
            attempt = 2;
          }
        }
      }

      await sleep(Math.round(Math.random() * 300));
    }

    ok = true;
    log(
      `抓取完成：新增 ${stats.added}，更新 ${stats.updated}，跳过 ${stats.skipped}，失败 ${stats.failed}` +
        (withImages ? `，下载图片 ${stats.images} 张` : '') +
        '。',
    );
  } catch (error) {
    log(`抓取中断：${error && error.stack ? error.stack : error}`);
    emit({ type: 'error', message: String(error && error.message ? error.message : error) });
    process.exitCode = 1;
  } finally {
    saveCookies(client.exportCookies());
    if (parser) await parser.close();
    if (runId) {
      db.finishScrapeRun(runId, {
        ...stats,
        status: ok ? 'done' : 'failed',
        message: ok ? null : '抓取未正常结束',
      });
    }
    emit({ type: 'done', stats, ok });
  }
}

main().catch((error) => {
  log(`致命错误：${error && error.stack ? error.stack : error}`);
  emit({ type: 'error', message: String(error && error.message ? error.message : error) });
  process.exitCode = 1;
});