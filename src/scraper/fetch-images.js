'use strict';

/**
 * 图片补抓：把数据库里仍是远程地址的封面图 / 步骤图下载到本地。
 *
 * 适用场景：
 *   - 之前用 --no-images 抓过；
 *   - 抓取时某几张图下载失败；
 *   - 想把已存在的远程图片一次性本地化。
 *
 * 用法：
 *   npm run fetch-images
 *   node --no-warnings src/scraper/fetch-images.js --size 1200 --only 106125193
 */

const db = require('../db');
const { localizeRecipeImages, imageStats } = require('./images');
const { sleep } = require('./session');

function log(message) {
  process.stdout.write(`[IMAGES] ${message}\n`);
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

function isRemote(url) {
  return typeof url === 'string' && /^https?:\/\//i.test(url);
}

function needsImages(recipe) {
  if (isRemote(recipe.coverImage)) return true;
  return (recipe.steps || []).some((step) => isRemote(step.image));
}

const formatBytes = (bytes) => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const size = args.size != null ? Number(args.size) : 1000;
  const delayMs = Number(args.delay || 250);
  const only = typeof args.only === 'string'
    ? new Set(args.only.split(',').map((value) => value.trim()).filter(Boolean))
    : null;

  let recipes = db.listAllRecipes();
  if (only) recipes = recipes.filter((recipe) => only.has(String(recipe.id)));

  const targets = recipes.filter(needsImages);
  log(`共 ${recipes.length} 道菜谱，其中 ${targets.length} 道还有远程图片待本地化。`);

  if (!targets.length) {
    const stats = imageStats();
    log(`本地已有 ${stats.count} 张图片，占用 ${formatBytes(stats.bytes)}，无需处理。`);
    return;
  }

  let downloaded = 0;
  let failed = 0;
  let bytes = 0;

  for (let index = 0; index < targets.length; index += 1) {
    const recipe = targets[index];
    const summary = await localizeRecipeImages(recipe, { size });

    downloaded += summary.downloaded;
    failed += summary.failed;
    bytes += summary.bytes;

    // collectedAt 保持不变，只是刷新图片地址
    db.upsertRecipe({ ...recipe, sourceUrl: recipe.sourceUrl });

    log(
      `(${index + 1}/${targets.length}) ${recipe.title || recipe.id} ｜下载 ${summary.downloaded}` +
        (summary.failed ? ` ｜失败 ${summary.failed}` : ''),
    );

    if (index < targets.length - 1) await sleep(delayMs);
  }

  const stats = imageStats();
  log(`完成：新下载 ${downloaded} 张，失败 ${failed} 张，新增 ${formatBytes(bytes)}。`);
  log(`本地图片合计 ${stats.count} 张，占用 ${formatBytes(stats.bytes)}。`);
}

main().catch((error) => {
  log(`出错：${error && error.stack ? error.stack : error}`);
  process.exitCode = 1;
});
