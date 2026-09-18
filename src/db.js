'use strict';

const { DatabaseSync } = require('node:sqlite');
const { PATHS, ensureDirs } = require('./paths');

ensureDirs();

const db = new DatabaseSync(PATHS.DB_FILE);

db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA synchronous = NORMAL');

db.exec(`
CREATE TABLE IF NOT EXISTS recipes (
  id           INTEGER PRIMARY KEY,
  url          TEXT NOT NULL,
  title        TEXT NOT NULL DEFAULT '',
  description  TEXT,
  cover_image  TEXT,
  author       TEXT,
  servings     TEXT,
  ingredients  TEXT NOT NULL DEFAULT '[]',
  ingredient_groups TEXT NOT NULL DEFAULT '{}',
  steps        TEXT NOT NULL DEFAULT '[]',
  tips         TEXT,
  tags         TEXT NOT NULL DEFAULT '[]',
  made_count   TEXT,
  fav_count    TEXT,
  search_text  TEXT NOT NULL DEFAULT '',
  source_url   TEXT,
  collected_at TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_recipes_title     ON recipes(title);
CREATE INDEX IF NOT EXISTS idx_recipes_collected ON recipes(collected_at);
CREATE INDEX IF NOT EXISTS idx_recipes_updated   ON recipes(updated_at);

CREATE TABLE IF NOT EXISTS scrape_runs (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  source_url  TEXT,
  status      TEXT NOT NULL DEFAULT 'running',
  total       INTEGER NOT NULL DEFAULT 0,
  added       INTEGER NOT NULL DEFAULT 0,
  updated     INTEGER NOT NULL DEFAULT 0,
  skipped     INTEGER NOT NULL DEFAULT 0,
  failed      INTEGER NOT NULL DEFAULT 0,
  message     TEXT,
  started_at  TEXT NOT NULL,
  finished_at TEXT
);

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
`);

/* 兼容老库：老 schema 没有 ingredient_groups 列，加上去 */
{
  const cols = db.prepare("PRAGMA table_info(recipes)").all();
  if (!cols.some((c) => c.name === 'ingredient_groups')) {
    db.exec("ALTER TABLE recipes ADD COLUMN ingredient_groups TEXT NOT NULL DEFAULT '{}'");
  }
}

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

const PUNCT_RE = /[,，、。;；:：|/\\_+()（）[\]【】{}<>"'“”‘’~!！?？@#$%^&*=]/g;

/* 调料/辅料白名单：常见于"辅料"/"调料"分组的食材。
 * 用于给老数据回填主辅料分组，以及 db.js 在缺失数据时兜底。 */
const SEASONING_KEYWORDS = new Set([
  // 基础调味
  '盐', '糖', '冰糖', '红糖', '白糖', '蜂蜜', '麦芽糖',
  '醋', '米醋', '香醋', '陈醋', '白醋', '苹果醋',
  '酱油', '生抽', '老抽', '蒸鱼豉油', '味极鲜', '蚝油', '甜面酱油',
  '料酒', '黄酒', '米酒', '白酒',
  // 油脂
  '油', '食用油', '植物油', '花生油', '玉米油', '菜籽油', '大豆油', '葵花籽油',
  '色拉油', '猪油', '黄油', '牛油', '羊油', '椰子油', '牛至油',
  '香油', '麻油', '芝麻油', '辣椒油', '花椒油', '藤椒油',
  // 香辛料
  '葱', '大葱', '小葱', '香葱', '葱花', '葱段', '葱末', '京葱',
  '姜', '生姜', '姜末', '姜丝', '姜片',
  '蒜', '大蒜', '蒜末', '蒜瓣', '蒜泥', '蒜蓉',
  '八角', '大料', '桂皮', '香叶', '花椒', '麻椒', '藤椒',
  '胡椒', '黑胡椒', '白胡椒', '胡椒粉',
  '辣椒', '干辣椒', '朝天椒', '小米辣', '小米椒', '辣椒粉', '辣椒面',
  '五香粉', '十三香', '卤料', '卤料包', '炖肉料', '卤汁',
  // 增鲜/酱料
  '味精', '鸡精', '鸡粉', '浓缩鸡汁', '太太乐',
  '豆瓣酱', '郫县豆瓣酱', '郫县豆瓣', '甜面酱', '黄豆酱', '豆瓣', '豆豉',
  '番茄酱', '番茄沙司', '沙拉酱', '辣椒酱', '老干妈', '海鲜酱', 'XO酱', '柱侯酱', '叉烧酱',
  // 淀粉/粉
  '淀粉', '玉米淀粉', '土豆淀粉', '红薯淀粉', '生粉', '糯米粉', '低筋面粉', '中筋面粉', '高筋面粉', '面粉',
  // 液体
  '水', '温水', '冷水', '热水', '清水', '冰水', '凉水',
  '高汤', '鸡汤', '骨汤', '肉汤', '鱼汤', '蔬菜汤', '浓汤宝',
  // 发酵/膨松
  '酵母', '泡打粉', '小苏打', '碱', '碱水',
  // 其他常见调料
  '茶叶', '茶叶蛋料包', '红茶', '绿茶', '普洱',
  '草果', '砂仁', '白蔻', '肉蔻', '丁香', '小茴香',
  '陈皮', '香茅', '罗勒', '迷迭香', '百里香', '欧芹',
  '香菜', '芹菜', '薄荷', '紫苏',
]);

/**
 * 判断一个用料名称是否属于"调料/辅料"。
 * 大前提：包含空格的复合作料（如"姜末"、"葱花"）也能命中白名单的根词。
 */
function isSeasoning(name) {
  if (!name) return false;
  const n = String(name).trim();
  if (!n) return false;
  if (SEASONING_KEYWORDS.has(n)) return true;
  // 复合名："姜末"、"葱花"、"蒜泥"、"郫县豆瓣酱" 等
  for (const kw of SEASONING_KEYWORDS) {
    if (n.includes(kw)) return true;
  }
  return false;
}

/**
 * 把平铺的 ingredients 按白名单启发式划成 main/seasoning。
 */
function classifyIngredients(ingredients) {
  const main = [];
  const seasoning = [];
  for (const item of ingredients || []) {
    if (!item || !item.name) continue;
    (isSeasoning(item.name) ? seasoning : main).push({ name: item.name, amount: item.amount || '' });
  }
  return { main, seasoning };
}

/**
 * 索引归一化：转小写并去掉所有空白与标点，
 * 这样“红烧 肉”这种跨词搜索也能命中“红烧肉”。
 */
function normalizeForIndex(value) {
  return String(value == null ? '' : value)
    .replace(/\u00a0/g, '')
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(PUNCT_RE, '');
}

/**
 * 查询词切分：标点视为词边界，得到若干关键词，彼此为 AND 关系。
 */
function tokenizeQuery(value) {
  return String(value == null ? '' : value)
    .replace(/\u00a0/g, ' ')
    .toLowerCase()
    .replace(/[-–—]/g, ' ')
    .replace(PUNCT_RE, ' ')
    .split(/\s+/)
    .map((token) => token.trim())
    .filter(Boolean);
}

function toArray(value) {
  return Array.isArray(value) ? value : [];
}

function buildSearchText(recipe) {
  const parts = [recipe.title, recipe.description, recipe.author, recipe.servings, recipe.tips];
  for (const item of toArray(recipe.ingredients)) {
    parts.push(item && item.name, item && item.amount);
  }
  for (const item of toArray(recipe.steps)) {
    parts.push(item && item.text);
  }
  parts.push(...toArray(recipe.tags));
  return normalizeForIndex(parts.filter(Boolean).join(' '));
}

function safeJson(value, fallback) {
  if (typeof value !== 'string') return fallback;
  try {
    const parsed = JSON.parse(value);
    return parsed == null ? fallback : parsed;
  } catch {
    return fallback;
  }
}

/**
 * 规范化分组：数据库里已有数据则补全缺项；老数据（默认空分组）则启发式重分类。
 */
function normalizeGroups(groups, ingredients) {
  const fallback = { main: [], seasoning: [] };
  let main = [];
  let seasoning = [];
  if (groups && Array.isArray(groups.main)) main = groups.main.filter((x) => x && x.name).map((n) => ({ name: n.name, amount: n.amount || '' }));
  if (groups && Array.isArray(groups.seasoning)) seasoning = groups.seasoning.filter((x) => x && x.name).map((n) => ({ name: n.name, amount: n.amount || '' }));

  const hasData = main.length > 0 || seasoning.length > 0;
  if (!hasData) {
    /* 老数据：DB 字段为空，按白名单兜底 */
    return classifyIngredients(ingredients);
  }

  /* 有数据但某一组缺失：把另一组没收录的、按白名单能识别的调料，补到缺失组 */
  if (!seasoning.length) {
    const mainNames = new Set(main.map((x) => x.name));
    for (const item of ingredients || []) {
      if (!item || !item.name) continue;
      if (mainNames.has(item.name)) continue;
      if (isSeasoning(item.name)) seasoning.push({ name: item.name, amount: item.amount || '' });
    }
  } else if (!main.length) {
    const seasonNames = new Set(seasoning.map((x) => x.name));
    for (const item of ingredients || []) {
      if (!item || !item.name) continue;
      if (seasonNames.has(item.name)) continue;
      if (!isSeasoning(item.name)) main.push({ name: item.name, amount: item.amount || '' });
    }
  }
  return { main, seasoning };
}

function rowToRecipe(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    url: row.url,
    title: row.title,
    description: row.description || '',
    coverImage: row.cover_image || '',
    author: row.author || '',
    servings: row.servings || '',
    ingredients: safeJson(row.ingredients, []),
    ingredientGroups: normalizeGroups(safeJson(row.ingredient_groups, null), safeJson(row.ingredients, [])),
    steps: safeJson(row.steps, []),
    tips: row.tips || '',
    tags: safeJson(row.tags, []),
    madeCount: row.made_count || '',
    favCount: row.fav_count || '',
    sourceUrl: row.source_url || '',
    collectedAt: row.collected_at,
    updatedAt: row.updated_at,
  };
}

/* ------------------------------------------------------------------ */
/* writes                                                              */
/* ------------------------------------------------------------------ */

const upsertStmt = db.prepare(`
  INSERT INTO recipes (
    id, url, title, description, cover_image, author, servings,
    ingredients, ingredient_groups, steps, tips, tags, made_count, fav_count,
    search_text, source_url, collected_at, updated_at
  ) VALUES (
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
  )
  ON CONFLICT(id) DO UPDATE SET
    url          = excluded.url,
    title        = excluded.title,
    description  = excluded.description,
    cover_image  = excluded.cover_image,
    author       = excluded.author,
    servings     = excluded.servings,
    ingredients  = excluded.ingredients,
    ingredient_groups = excluded.ingredient_groups,
    steps        = excluded.steps,
    tips         = excluded.tips,
    tags         = excluded.tags,
    made_count   = excluded.made_count,
    fav_count    = excluded.fav_count,
    search_text  = excluded.search_text,
    source_url   = excluded.source_url,
    updated_at   = excluded.updated_at
`);

const existsStmt = db.prepare('SELECT id, updated_at FROM recipes WHERE id = ?');

/**
 * 写入或更新一条菜谱。
 * @returns {'added'|'updated'}
 */
function upsertRecipe(recipe) {
  const now = new Date().toISOString();
  const existed = existsStmt.get(String(recipe.id));

  const groups = recipe.ingredientGroups
    || classifyIngredients(recipe.ingredients);
  upsertStmt.run(
    String(recipe.id),
    recipe.url || '',
    recipe.title || '',
    recipe.description || '',
    recipe.coverImage || '',
    recipe.author || '',
    recipe.servings || '',
    JSON.stringify(toArray(recipe.ingredients)),
    JSON.stringify({
      main: toArray(groups.main).filter((x) => x && x.name),
      seasoning: toArray(groups.seasoning).filter((x) => x && x.name),
    }),
    JSON.stringify(toArray(recipe.steps)),
    recipe.tips || '',
    JSON.stringify(toArray(recipe.tags)),
    recipe.madeCount || '',
    recipe.favCount || '',
    buildSearchText(recipe),
    recipe.sourceUrl || '',
    recipe.collectedAt || now,
    now,
  );

  return existed ? 'updated' : 'added';
}

function hasRecipe(id) {
  return Boolean(existsStmt.get(String(id)));
}

function deleteRecipe(id) {
  return db.prepare('DELETE FROM recipes WHERE id = ?').run(String(id)).changes > 0;
}

/**
 * 删除菜谱，并返回被引用过的本地图片路径（/images/covers/... 或 /images/steps/...）。
 * 文件清理由调用方负责（这里只负责查询 + 删行）。
 */
function deleteRecipeWithImages(id) {
  const row = db
    .prepare('SELECT cover_image, steps FROM recipes WHERE id = ?')
    .get(String(id));
  if (!row) return { ok: false, images: [] };
  const images = [];
  if (row.cover_image) images.push(row.cover_image);
  let steps = [];
  try { steps = JSON.parse(row.steps || '[]'); } catch { /* ignore */ }
  for (const s of steps) if (s && s.image) images.push(s.image);
  const result = db.prepare('DELETE FROM recipes WHERE id = ?').run(String(id));
  return { ok: result.changes > 0, images };
}

/**
 * 把菜谱的 updated_at 设为当前时间，让"按更新时间"排序时浮到最前。
 * @returns {boolean} 是否命中
 */
function touchRecipe(id) {
  const now = new Date().toISOString();
  return db
    .prepare('UPDATE recipes SET updated_at = ? WHERE id = ?')
    .run(now, String(id)).changes > 0;
}

/* ------------------------------------------------------------------ */
/* reads                                                               */
/* ------------------------------------------------------------------ */

const SORTS = {
  collected: 'r.collected_at',
  updated: 'r.updated_at',
  title: 'r.title COLLATE NOCASE',
  ingredients: 'json_array_length(r.ingredients)',
  steps: 'json_array_length(r.steps)',
  id: 'r.id',
  random: 'RANDOM()',
};

function buildWhere({ q, tag, ids }) {
  const clauses = [];
  const params = [];

  for (const token of tokenizeQuery(q)) {
    clauses.push('r.search_text LIKE ?');
    params.push(`%${token}%`);
  }

  if (tag) {
    clauses.push('r.tags LIKE ?');
    params.push(`%"${tag}"%`);
  }

  if (Array.isArray(ids) && ids.length) {
    clauses.push(`r.id IN (${ids.map(() => '?').join(',')})`);
    params.push(...ids.map(String));
  }

  return {
    sql: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '',
    params,
  };
}

function queryRecipes(options = {}) {
  const {
    q = '',
    tag = '',
    sort = 'collected',
    order = 'desc',
    page = 1,
    pageSize = 24,
  } = options;

  const dir = String(order).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
  const sortSql = SORTS[sort] || SORTS.collected;
  const { sql: whereSql, params } = buildWhere({ q, tag, ids: options.ids });
  const safePage = Math.max(1, Number(page) || 1);
  const safeSize = Math.min(100, Math.max(1, Number(pageSize) || 24));

  const total = db
    .prepare(`SELECT COUNT(*) AS c FROM recipes r ${whereSql}`)
    .get(...params).c;

  const rows = db
    .prepare(
      `SELECT r.* FROM recipes r ${whereSql}
       ORDER BY (${sortSql}) ${dir}, r.id ASC
       LIMIT ? OFFSET ?`,
    )
    .all(...params, safeSize, (safePage - 1) * safeSize);

  return {
    total: Number(total),
    page: safePage,
    pageSize: safeSize,
    pageCount: Math.max(1, Math.ceil(Number(total) / safeSize)),
    items: rows.map(rowToRecipe),
  };
}

function getRecipe(id) {
  return rowToRecipe(db.prepare('SELECT * FROM recipes WHERE id = ?').get(String(id)));
}

function listRecipesBySource(sourceUrl) {
  return db
    .prepare('SELECT id, updated_at FROM recipes WHERE source_url = ?')
    .all(sourceUrl)
    .map((row) => ({ id: Number(row.id), updatedAt: row.updated_at }));
}

function listAllIds() {
  return db.prepare('SELECT id FROM recipes').all().map((row) => Number(row.id));
}

function listAllRecipes() {
  return db.prepare('SELECT * FROM recipes ORDER BY id ASC').all().map(rowToRecipe);
}

function getTags(limit = 80) {
  const counter = new Map();
  for (const row of db.prepare('SELECT tags FROM recipes').all()) {
    for (const tag of safeJson(row.tags, [])) {
      if (!tag) continue;
      counter.set(tag, (counter.get(tag) || 0) + 1);
    }
  }
  return [...counter.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name, 'zh'))
    .slice(0, limit);
}

function getStats() {
  const base = db
    .prepare(
      `SELECT
         COUNT(*) AS total,
         SUM(CASE WHEN ingredients <> '[]' THEN 1 ELSE 0 END) AS withIngredients,
         SUM(CASE WHEN steps <> '[]' THEN 1 ELSE 0 END) AS withSteps,
         MAX(collected_at) AS lastCollected
       FROM recipes`,
    )
    .get();

  const lastRun = db
    .prepare('SELECT * FROM scrape_runs ORDER BY id DESC LIMIT 1')
    .get();

  return {
    total: Number(base.total || 0),
    withIngredients: Number(base.withIngredients || 0),
    withSteps: Number(base.withSteps || 0),
    lastCollected: base.lastCollected || null,
    lastRun: lastRun
      ? {
          id: Number(lastRun.id),
          sourceUrl: lastRun.source_url,
          status: lastRun.status,
          total: Number(lastRun.total),
          added: Number(lastRun.added),
          updated: Number(lastRun.updated),
          skipped: Number(lastRun.skipped),
          failed: Number(lastRun.failed),
          message: lastRun.message,
          startedAt: lastRun.started_at,
          finishedAt: lastRun.finished_at,
        }
      : null,
  };
}

/* ------------------------------------------------------------------ */
/* scrape runs                                                         */
/* ------------------------------------------------------------------ */

function startScrapeRun(sourceUrl) {
  const info = db
    .prepare('INSERT INTO scrape_runs (source_url, status, started_at) VALUES (?, ?, ?)')
    .run(sourceUrl || '', 'running', new Date().toISOString());
  return Number(info.lastInsertRowid);
}

function finishScrapeRun(id, patch = {}) {
  db.prepare(
    `UPDATE scrape_runs
        SET status = ?, total = ?, added = ?, updated = ?, skipped = ?, failed = ?,
            message = ?, finished_at = ?
      WHERE id = ?`,
  ).run(
    patch.status || 'done',
    patch.total || 0,
    patch.added || 0,
    patch.updated || 0,
    patch.skipped || 0,
    patch.failed || 0,
    patch.message || null,
    new Date().toISOString(),
    id,
  );
}

/* ------------------------------------------------------------------ */
/* meta                                                                */
/* ------------------------------------------------------------------ */

function setMeta(key, value) {
  db.prepare(
    'INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
  ).run(key, String(value));
}

function getMeta(key, fallback = null) {
  const row = db.prepare('SELECT value FROM meta WHERE key = ?').get(key);
  return row ? row.value : fallback;
}

module.exports = {
  db,
  upsertRecipe,
  hasRecipe,
  deleteRecipe,
  deleteRecipeWithImages,
  touchRecipe,
  queryRecipes,
  getRecipe,
  listRecipesBySource,
  listAllIds,
  listAllRecipes,
  getTags,
  getStats,
  startScrapeRun,
  finishScrapeRun,
  setMeta,
  getMeta,
  buildSearchText,
};
