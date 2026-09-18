'use strict';
/**
 * 把已有菜谱的 ingredients 用白名单启发式回填到 ingredient_groups。
 * 已有的真实分组（来自抓取）不会被覆盖。
 *
 *   node src/scripts/backfill-ingredient-groups.js
 *   node src/scripts/backfill-ingredient-groups.js --dry-run   # 只统计不改库
 */

const { db } = require('../db');

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');

function classify(ingredients) {
  const main = [];
  const seasoning = [];
  for (const item of ingredients || []) {
    if (!item || !item.name) continue;
    const clean = { name: item.name, amount: item.amount || '' };
    if (isSeasoning(clean.name)) seasoning.push(clean);
    else main.push(clean);
  }
  return { main, seasoning };
}

const SEASONING_KEYWORDS = new Set([
  '盐', '糖', '冰糖', '红糖', '白糖', '蜂蜜', '麦芽糖',
  '醋', '米醋', '香醋', '陈醋', '白醋', '苹果醋',
  '酱油', '生抽', '老抽', '蒸鱼豉油', '味极鲜', '蚝油', '甜面酱油',
  '料酒', '黄酒', '米酒', '白酒',
  '油', '食用油', '植物油', '花生油', '玉米油', '菜籽油', '大豆油', '葵花籽油',
  '色拉油', '猪油', '黄油', '牛油', '羊油', '椰子油',
  '香油', '麻油', '芝麻油', '辣椒油', '花椒油', '藤椒油',
  '葱', '大葱', '小葱', '香葱', '葱花', '葱段', '葱末', '京葱',
  '姜', '生姜', '姜末', '姜丝', '姜片',
  '蒜', '大蒜', '蒜末', '蒜瓣', '蒜泥', '蒜蓉',
  '八角', '大料', '桂皮', '香叶', '花椒', '麻椒', '藤椒',
  '胡椒', '黑胡椒', '白胡椒', '胡椒粉',
  '辣椒', '干辣椒', '朝天椒', '小米辣', '小米椒', '辣椒粉', '辣椒面',
  '五香粉', '十三香', '卤料', '卤料包', '炖肉料',
  '味精', '鸡精', '鸡粉', '浓缩鸡汁',
  '豆瓣酱', '郫县豆瓣酱', '郫县豆瓣', '甜面酱', '黄豆酱', '豆瓣', '豆豉',
  '番茄酱', '番茄沙司', '沙拉酱', '辣椒酱', '老干妈', '海鲜酱', 'XO酱', '柱侯酱', '叉烧酱',
  '淀粉', '玉米淀粉', '土豆淀粉', '红薯淀粉', '生粉', '糯米粉',
  '低筋面粉', '中筋面粉', '高筋面粉', '面粉',
  '水', '温水', '冷水', '热水', '清水', '冰水', '凉水',
  '高汤', '鸡汤', '骨汤', '肉汤', '鱼汤', '蔬菜汤', '浓汤宝',
  '酵母', '泡打粉', '小苏打', '碱', '碱水',
  '茶叶', '茶叶蛋料包', '红茶', '绿茶', '普洱',
  '草果', '砂仁', '白蔻', '肉蔻', '丁香', '小茴香',
  '陈皮', '香茅', '罗勒', '迷迭香', '百里香', '欧芹',
  '香菜', '芹菜', '薄荷', '紫苏',
]);

function isSeasoning(name) {
  if (!name) return false;
  const n = String(name).trim();
  if (!n) return false;
  if (SEASONING_KEYWORDS.has(n)) return true;
  for (const kw of SEASONING_KEYWORDS) if (n.includes(kw)) return true;
  return false;
}

function hasRealGroups(groups) {
  if (!groups || typeof groups !== 'object') return false;
  const main = Array.isArray(groups.main) ? groups.main : [];
  const seasoning = Array.isArray(groups.seasoning) ? groups.seasoning : [];
  return main.length > 0 || seasoning.length > 0;
}

const rows = db.prepare("SELECT id, ingredients, ingredient_groups FROM recipes").all();
console.log(`共 ${rows.length} 条菜谱，${dryRun ? '预览' : '开始回填'}...`);

const updateStmt = db.prepare("UPDATE recipes SET ingredient_groups = ? WHERE id = ?");

let updated = 0;
let skipped = 0;
let noIngredients = 0;
let mainTotal = 0;
let seasoningTotal = 0;
let allMain = 0;
let allSeasoning = 0;
let mixed = 0;

const batch = [];
for (const row of rows) {
  let ingredients = [];
  try { ingredients = JSON.parse(row.ingredients || '[]'); } catch { ingredients = []; }
  if (!Array.isArray(ingredients) || ingredients.length === 0) {
    noIngredients += 1;
    continue;
  }

  let existing = null;
  try { existing = JSON.parse(row.ingredient_groups || '{}'); } catch { existing = null; }

  let groups;
  if (hasRealGroups(existing)) {
    skipped += 1;
    groups = existing;
  } else {
    groups = classify(ingredients);
    updated += 1;
    if (!dryRun) batch.push({ id: row.id, groups: JSON.stringify(groups) });
  }

  mainTotal += groups.main.length;
  seasoningTotal += groups.seasoning.length;
  if (groups.seasoning.length === 0) allMain += 1;
  else if (groups.main.length === 0) allSeasoning += 1;
  else mixed += 1;
}

if (!dryRun && batch.length) {
  db.exec('BEGIN');
  try {
    for (const r of batch) updateStmt.run(r.groups, r.id);
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

console.log(`\n=== 结果 ===`);
console.log(`已回填: ${updated}`);
console.log(`已有数据跳过: ${skipped}`);
console.log(`无配料跳过: ${noIngredients}`);
console.log(`干运行: ${dryRun ? '是（未写入）' : '否（已写入）'}`);
console.log(`\n=== 分布 ===`);
console.log(`全是主料: ${allMain}`);
console.log(`全是调料: ${allSeasoning}`);
console.log(`主+调: ${mixed}`);
console.log(`平均 主料 ${(mainTotal / rows.length).toFixed(1)} / 调料 ${(seasoningTotal / rows.length).toFixed(1)}`);