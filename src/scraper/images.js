'use strict';

/**
 * 图片本地化：把下厨房图床上的封面图 / 步骤图下载到 data/images/ 下，
 * 数据库中保存的是本地相对地址（如 /images/covers/106125193.jpg），
 * 这样离线也能看图，不再依赖外部图床。
 */

const fs = require('node:fs');
const path = require('node:path');
const { PATHS, ensureDirs } = require('../paths');
const { USER_AGENT } = require('./browser');

const REFERER = 'https://www.xiachufang.com/';

const EXT_BY_TYPE = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/pjpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/avif': 'avif',
  'image/bmp': 'bmp',
};

/**
 * 下厨房图床地址形如 `<hash>_3000w_4000h.jpg`。
 * size > 0 时换成一个更小的尺寸，避免把 3000px 的原图全存到本地。
 */
function resizeUrl(url, size) {
  if (!size) return url;
  const match = /^(.*)_(\d+)w_(\d+)h(\.[a-z0-9]+)$/i.exec(url);
  if (!match) return url;
  const width = Number(match[2]);
  const height = Number(match[3]);
  if (!width || width <= size) return url;
  return `${match[1]}_${size}w_${Math.round((height * size) / width)}h${match[4]}`;
}

function extFromUrl(url) {
  const match = /\.([a-z0-9]{2,5})(?:$|[?#])/i.exec(url);
  return match ? match[1].toLowerCase() : '';
}

async function fetchImage(url, timeout) {
  const response = await fetch(url, {
    headers: {
      Referer: REFERER,
      'User-Agent': USER_AGENT,
      Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(timeout),
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length < 64) throw new Error('图片内容为空');

  const type = String(response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  return { buffer, type };
}

/**
 * 下载单张图片。
 * @returns {Promise<{ok:true, publicPath:string, bytes:number, source:string}|{ok:false, error:string}>}
 */
async function downloadImage(url, { dir, name, size = 0, timeout = 20000 } = {}) {
  if (!/^https?:\/\//i.test(String(url || ''))) {
    // 已经是本地地址，无需下载
    return { ok: true, publicPath: url, bytes: 0, source: url, skipped: true };
  }

  ensureDirs();

  const candidates = size ? [resizeUrl(url, size), url] : [url];
  let lastError = null;

  for (const candidate of candidates) {
    try {
      const { buffer, type } = await fetchImage(candidate, timeout);
      const ext = EXT_BY_TYPE[type] || extFromUrl(candidate) || 'jpg';
      const file = `${name}.${ext}`;
      const target = path.join(dir, file);

      fs.writeFileSync(target, buffer);

      const rel = path.relative(PATHS.IMAGE_DIR, target).split(path.sep).join('/');
      return { ok: true, publicPath: `/images/${rel}`, bytes: buffer.length, source: candidate };
    } catch (error) {
      lastError = error;
    }
  }

  return { ok: false, error: lastError ? lastError.message : '未知错误' };
}

/**
 * 把一条菜谱里的封面图与步骤图下载到本地，就地替换成 /images/... 地址。
 * @returns {Promise<{downloaded:number, failed:number, bytes:number, warnings:string[]}>}
 */
async function localizeRecipeImages(recipe, { size = 1000, timeout = 20000 } = {}) {
  const summary = { downloaded: 0, failed: 0, bytes: 0, warnings: [] };

  if (recipe.coverImage) {
    const result = await downloadImage(recipe.coverImage, {
      dir: PATHS.COVER_DIR,
      name: String(recipe.id),
      size,
      timeout,
    });
    if (result.ok) {
      recipe.coverImage = result.publicPath;
      if (!result.skipped) {
        summary.downloaded += 1;
        summary.bytes += result.bytes;
      }
    } else {
      summary.failed += 1;
      summary.warnings.push(`封面图下载失败(${result.error})`);
    }
  }

  for (const step of recipe.steps || []) {
    if (!step.image) continue;
    const result = await downloadImage(step.image, {
      dir: PATHS.STEP_DIR,
      name: `${recipe.id}-${step.index}`,
      size,
      timeout,
    });
    if (result.ok) {
      step.image = result.publicPath;
      if (!result.skipped) {
        summary.downloaded += 1;
        summary.bytes += result.bytes;
      }
    } else {
      summary.failed += 1;
    }
  }

  if (summary.failed) {
    summary.warnings.push(`步骤图 ${summary.failed} 张下载失败`);
  }

  return summary;
}

/** 统计本地已缓存的图片数量与占用空间 */
function imageStats() {
  const result = { count: 0, bytes: 0 };
  for (const dir of [PATHS.COVER_DIR, PATHS.STEP_DIR]) {
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (!entry.isFile()) continue;
      try {
        result.bytes += fs.statSync(path.join(dir, entry.name)).size;
        result.count += 1;
      } catch {
        /* ignore */
      }
    }
  }
  return result;
}

module.exports = {
  downloadImage,
  localizeRecipeImages,
  resizeUrl,
  imageStats,
  EXT_BY_TYPE,
};
