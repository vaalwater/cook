#!/usr/bin/env node
/**
 * 把 iOS App 里导出的备份同步回本地菜谱库（SQLite + data/images）。
 *
 * 背景：App 里的删除、刷新更新时间、待做清单、以及手机上现场抓的新菜谱都只存在手机沙盒里，
 * 重装 / 换机就会丢。导出一份 JSON 备份，再用这个脚本写回电脑库，形成双向：
 *   电脑抓 → 导出种子 → 手机看 / 手机抓 → 导出备份 → 回写电脑库
 *
 * 用法：
 *   npm run import:ios -- 菜谱备份.json
 *   npm run import:ios -- 菜谱备份.json --dry-run      # 只看会做什么，不写库
 *   npm run import:ios -- 菜谱备份.json --no-delete    # 不处理 App 里删掉的菜谱
 *
 * 备份文件结构（App 导出）：
 *   { "exportedAt": "2026-10-20T...", "recipes": [...], "plan": [{id,title,addedAt}], "deleted": [12345] }
 *
 * 合并规则：
 *   - 菜谱：只有备份里的 updatedAt 比本地新（或本地没有这条）时才写，避免覆盖电脑端更新的内容
 *   - 删除：App 里删掉的 id 在本地也删掉（连带删 data/images 里被引用的文件），--no-delete 可跳过
 *   - 待做清单：存进 meta 表的 app.plan
 */

const fs = require('node:fs');
const path = require('node:path');

const PATHS = require('../paths');
const db = require('../db');

function parseArgs(argv) {
  const opts = { file: null, dryRun: false, noDelete: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--dry-run') opts.dryRun = true;
    else if (arg === '--no-delete') opts.noDelete = true;
    else if (!arg.startsWith('-')) opts.file = arg;
  }
  return opts;
}

function stamp(value) {
  if (!value) return 0;
  const t = Date.parse(value);
  return Number.isFinite(t) ? t : 0;
}

function readBackup(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const recipes = Array.isArray(raw.recipes) ? raw.recipes : [];
  const deleted = Array.isArray(raw.deleted) ? raw.deleted : [];
  const plan = Array.isArray(raw.plan) ? raw.plan : [];
  return {
    exportedAt: raw.exportedAt || '',
    recipes: recipes.filter((r) => r && Number.isFinite(Number(r.id))),
    deleted: deleted.map(Number).filter((n) => Number.isFinite(n)),
    plan,
  };
}

/** 删掉本地图片文件（只处理 /images/ 开头的本地路径） */
function removeLocalImage(publicPath) {
  if (typeof publicPath !== 'string' || !publicPath.startsWith('/images/')) return false;
  const rel = publicPath.replace(/^\/images\//, '');
  const abs = path.join(PATHS.IMAGE_DIR, rel);
  if (!abs.startsWith(PATHS.IMAGE_DIR)) return false;
  if (!fs.existsSync(abs)) return false;
  fs.unlinkSync(abs);
  return true;
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!opts.file) {
    console.error('用法：npm run import:ios -- <备份文件.json> [--dry-run] [--no-delete]');
    process.exit(1);
  }
  if (!fs.existsSync(opts.file)) {
    console.error(`找不到备份文件：${opts.file}`);
    process.exit(1);
  }

  const backup = readBackup(opts.file);
  console.log(`备份导出时间：${backup.exportedAt || '-'}`);
  console.log(`菜谱 ${backup.recipes.length} 条，删除标记 ${backup.deleted.length} 条，待做 ${backup.plan.length} 条`);
  if (opts.dryRun) console.log('（dry-run：不会写库）\n');

  let added = 0;
  let updated = 0;
  let skipped = 0;

  for (const recipe of backup.recipes) {
    const id = Number(recipe.id);
    const local = db.getRecipe(id);
    if (local && stamp(local.updatedAt) > stamp(recipe.updatedAt)) {
      skipped += 1;
      continue;
    }
    if (opts.dryRun) {
      if (local) updated += 1; else added += 1;
      continue;
    }
    const outcome = db.upsertRecipe(recipe);
    if (outcome === 'added') added += 1; else updated += 1;
  }

  let removed = 0;
  let removedImages = 0;
  if (!opts.noDelete) {
    for (const id of backup.deleted) {
      if (opts.dryRun) {
        if (db.hasRecipe(id)) removed += 1;
        continue;
      }
      const result = db.deleteRecipeWithImages(id);
      if (!result.ok) continue;
      removed += 1;
      for (const image of result.images) {
        if (removeLocalImage(image)) removedImages += 1;
      }
    }
  }

  if (!opts.dryRun && backup.plan.length) {
    db.setMeta('app.plan', JSON.stringify(backup.plan));
  }

  const stats = db.getStats();
  console.log(`新增 ${added}，更新 ${updated}，跳过（本地更新）${skipped}`);
  console.log(`删除 ${removed}，清理图片 ${removedImages}`);
  console.log(`库里现在共 ${stats.total} 条菜谱`);
  if (opts.dryRun) console.log('\n确认无误后去掉 --dry-run 再跑一次');
}

main();
