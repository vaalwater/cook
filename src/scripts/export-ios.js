'use strict';

/**
 * 把本地菜谱库（SQLite + data/images）导出成 iOS App 可以直接打包的种子数据。
 *
 * 产物：
 *   <out>/recipes.json          全部菜谱（与 /api/recipes 返回的字段一致）
 *   <out>/images/...            菜谱引用的本地图片（默认压缩，控制安装包体积）
 *   <out>/manifest.json         导出信息（数量 / 体积 / 远程图片数）
 *
 * 用法：
 *   npm run export:ios
 *   npm run export:ios -- --original            # 不压缩，直接拷原图
 *   npm run export:ios -- --cover-size 900 --step-size 800 --quality 70
 */

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const db = require('../db');
const { PATHS } = require('../paths');

const DEFAULT_OUT = path.join(PATHS.ROOT_DIR, 'ios', 'RecipeBook', 'RecipeBook', 'Resources', 'Seed');

function parseArgs(argv) {
  const opts = {
    out: DEFAULT_OUT,
    original: false,
    coverSize: 720,
    stepSize: 640,
    quality: 55,
    force: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--out':
        opts.out = path.resolve(String(next));
        i += 1;
        break;
      case '--original':
        opts.original = true;
        break;
      case '--force':
        opts.force = true;
        break;
      case '--cover-size':
        opts.coverSize = Number(next);
        i += 1;
        break;
      case '--step-size':
        opts.stepSize = Number(next);
        i += 1;
        break;
      case '--quality':
        opts.quality = Number(next);
        i += 1;
        break;
      default:
        break;
    }
  }
  return opts;
}

function formatBytes(bytes) {
  const value = Number(bytes || 0);
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 * 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB`;
  return `${(value / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** 用 macOS 自带 sips 缩放 + 改 JPEG 质量；失败则退回直接拷贝 */
function compressImage(src, dst, maxEdge, quality) {
  try {
    execFileSync(
      'sips',
      ['-Z', String(maxEdge), '-s', 'formatOptions', String(quality), src, '--out', dst],
      { stdio: 'ignore' },
    );
    return fs.existsSync(dst);
  } catch {
    return false;
  }
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const outDir = opts.out;

  const recipes = db.listAllRecipes();
  if (!recipes.length) {
    console.log('本地库里没有菜谱，先跑 npm run scrape 抓一些再来。');
    return;
  }

  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const jsonPath = path.join(outDir, 'recipes.json');
  fs.writeFileSync(jsonPath, JSON.stringify(recipes));
  console.log(`菜谱：${recipes.length} 条 → ${jsonPath}（${formatBytes(fs.statSync(jsonPath).size)}）`);

  /* 收集被引用到的图片，区分本地 / 远程 */
  const localPaths = new Set();
  let remoteCount = 0;
  for (const recipe of recipes) {
    if (recipe.coverImage) {
      if (recipe.coverImage.startsWith('/images/')) localPaths.add(recipe.coverImage);
      else if (/^https?:\/\//i.test(recipe.coverImage)) remoteCount += 1;
    }
    for (const step of recipe.steps || []) {
      if (!step || !step.image) continue;
      if (step.image.startsWith('/images/')) localPaths.add(step.image);
      else if (/^https?:\/\//i.test(step.image)) remoteCount += 1;
    }
  }

  let bytes = 0;
  let copied = 0;
  let missing = 0;
  const list = [...localPaths].sort();

  for (const [i, publicPath] of list.entries()) {
    const rel = publicPath.replace(/^\/images\//, '');
    const src = path.join(PATHS.IMAGE_DIR, rel);
    const dst = path.join(outDir, 'images', rel);

    if (!fs.existsSync(src)) {
      missing += 1;
      continue;
    }

    fs.mkdirSync(path.dirname(dst), { recursive: true });
    const isCover = rel.startsWith('covers/');
    const maxEdge = isCover ? opts.coverSize : opts.stepSize;

    let ok = false;
    if (opts.original || maxEdge <= 0) {
      fs.copyFileSync(src, dst);
      ok = true;
    } else {
      ok = compressImage(src, dst, maxEdge, opts.quality);
      if (!ok) fs.copyFileSync(src, dst);
    }
    if (ok) {
      bytes += fs.statSync(dst).size;
      copied += 1;
    }
    if ((i + 1) % 300 === 0 || i + 1 === list.length) {
      process.stdout.write(`  图片 ${i + 1}/${list.length}\r`);
    }
  }

  const manifest = {
    exportedAt: new Date().toISOString(),
    recipeCount: recipes.length,
    imageCount: copied,
    imageBytes: bytes,
    missingImages: missing,
    remoteImages: remoteCount,
    compressed: !opts.original,
    coverSize: opts.coverSize,
    stepSize: opts.stepSize,
    quality: opts.quality,
  };
  fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2));

  console.log(`\n图片：${copied} 张 / ${formatBytes(bytes)}（引用 ${list.length} 张，缺 ${missing} 张，远程 ${remoteCount} 张）`);
  console.log(`输出目录：${outDir}`);
}

main();
