'use strict';

/* ------------------------------------------------------------------ */
/* 状态                                                                */
/* ------------------------------------------------------------------ */

const state = {
  q: '',
  tag: '',
  sort: 'updated',
  order: 'desc',
  page: 1,
  pageSize: 24,
  total: 0,
  items: [],
};

const $ = (id) => document.getElementById(id);

const el = {
  brandSub: $('brandSub'),
  searchInput: $('searchInput'),
  searchClear: $('searchClear'),
  sortSelect: $('sortSelect'),
  orderToggle: $('orderToggle'),
  orderLabel: $('orderLabel'),
  pageSizeSelect: $('pageSizeSelect'),
  tagList: $('tagList'),
  tagToggle: $('tagToggle'),
  clearTag: $('clearTag'),
  resultSummary: $('resultSummary'),
  activeFilters: $('activeFilters'),
  grid: $('grid'),
  emptyState: $('emptyState'),
  pagination: $('pagination'),
  btnLogin: $('btnLogin'),
  btnImages: $('btnImages'),
  btnScrape: $('btnScrape'),
  drawer: $('drawer'),
  drawerBackdrop: $('drawerBackdrop'),
  drawerBody: $('drawerBody'),
  drawerClose: $('drawerClose'),
  drawerDelete: $('drawerDelete'),
  drawerSource: $('drawerSource'),
  drawerTouch: $('drawerTouch'),
  drawerPlan: $('drawerPlan'),
  jobPanel: $('jobPanel'),
  jobLog: $('jobLog'),
  jobTitle: $('jobTitle'),
  jobProgress: $('jobProgress'),
  jobStatusDot: $('jobStatusDot'),
  jobCancel: $('jobCancel'),
  jobToggle: $('jobToggle'),
  scrapeModal: $('scrapeModal'),
  scrapeCancel: $('scrapeCancel'),
  scrapeConfirm: $('scrapeConfirm'),
  optIds: $('optIds'),
  optDelay: $('optDelay'),
  optForce: $('optForce'),
  optDebug: $('optDebug'),
  optImages: $('optImages'),
  optImageSize: $('optImageSize'),
  sessionHint: $('sessionHint'),
  planBar: $('planBar'),
  planCount: $('planCount'),
  btnPlanClear: $('btnPlanClear'),
  btnCookStart: $('btnCookStart'),
  planModal: $('planModal'),
  planList: $('planList'),
  planCancel: $('planCancel'),
  planClearAll: $('planClearAll'),
  planStart: $('planStart'),
  cookMode: $('cookMode'),
  cookBack: $('cookBack'),
  cookSummary: $('cookSummary'),
  cookMainList: $('cookMainList'),
  cookSeasonList: $('cookSeasonList'),
  cookTimeline: $('cookTimeline'),
  cookTimelineMeta: $('cookTimelineMeta'),
  cookOrderStrip: $('cookOrderStrip'),
  cookOrderMeta: $('cookOrderMeta'),
  cookRecipes: $('cookRecipes'),
  cookPlanManage: $('cookPlanManage'),
  cookPlanCount: $('cookPlanCount'),
};

/* ------------------------------------------------------------------ */
/* 工具                                                                */
/* ------------------------------------------------------------------ */

function esc(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** 本地图片（/images/...）直接使用，远程地址才走后端代理 */
function imageUrl(url) {
  if (!url) return '';
  if (url.startsWith('/')) return url;
  return `/api/image?url=${encodeURIComponent(url)}`;
}

function jobTitle(kind) {
  if (kind === 'login') return '登录下厨房';
  if (kind === 'images') return '补抓图片';
  return '抓取菜谱';
}

function formatTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(
    date.getHours(),
  )}:${pad(date.getMinutes())}`;
}

function formatBytes(bytes) {
  const value = Number(bytes || 0);
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 * 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB`;
  return `${(value / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

async function api(path, options) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `请求失败 (${response.status})`);
  return data;
}

function debounce(fn, wait) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), wait);
  };
}

/* ------------------------------------------------------------------ */
/* 数据加载                                                            */
/* ------------------------------------------------------------------ */

async function loadStats() {
  try {
    const stats = await api('/api/stats');
    const parts = [`本地共 ${stats.total} 道菜谱`];
    if (stats.images && stats.images.count) {
      parts.push(`图片 ${stats.images.count} 张 / ${formatBytes(stats.images.bytes)}`);
    }
    if (stats.lastCollected) parts.push(`最近抓取 ${formatTime(stats.lastCollected)}`);
    if (stats.lastRun && stats.lastRun.status === 'failed') parts.push('上次抓取未正常结束');
    el.brandSub.textContent = parts.join(' · ');
  } catch {
    el.brandSub.textContent = '无法读取统计信息';
  }
}

async function loadTags() {
  try {
    const tags = await api('/api/tags?limit=60');
    if (!tags.length) {
      el.tagList.innerHTML = '<span class="tag" style="cursor:default;opacity:.6">暂无标签</span>';
      el.tagToggle.hidden = true;
      el.tagList.dataset.expanded = 'false';
      return;
    }
    el.tagList.innerHTML = tags
      .map(
        (tag) =>
          `<button class="tag${state.tag === tag.name ? ' active' : ''}" type="button" data-tag="${esc(
            tag.name,
          )}">${esc(tag.name)}<span class="count">${tag.count}</span></button>`,
      )
      .join('');
    /* 渲染后再判断是否需要展开按钮（必须等浏览器排版） */
    requestAnimationFrame(updateTagToggle);
  } catch {
    el.tagList.innerHTML = '';
    el.tagToggle.hidden = true;
  }
}

function updateTagToggle() {
  if (!el.tagToggle || !el.tagList) return;
  const collapsed = el.tagList.dataset.expanded !== 'true';
  el.tagList.dataset.expanded = collapsed ? 'false' : 'true';
  // 让 max-height 先应用再读高度
  requestAnimationFrame(() => {
    const overflow = el.tagList.scrollHeight - el.tagList.clientHeight > 4;
    el.tagToggle.hidden = !overflow;
    el.tagToggle.textContent = collapsed ? '展开 ▾' : '收起 ▴';
  });
}

async function loadSessionHint() {
  try {
    const session = await api('/api/session');
    if (!session.saved || !session.hasSession) {
      el.sessionHint.textContent = '当前没有可用的登录态，开始抓取时会先弹出浏览器等你登录。';
      el.sessionHint.classList.add('warn');
    } else {
      el.sessionHint.textContent = `已保存登录态（${formatTime(session.savedAt)}），可直接抓取。`;
      el.sessionHint.classList.remove('warn');
    }
  } catch {
    el.sessionHint.textContent = '';
  }
}

async function loadRecipes() {
  const params = new URLSearchParams({
    q: state.q,
    tag: state.tag,
    sort: state.sort,
    order: state.order,
    page: String(state.page),
    pageSize: String(state.pageSize),
  });

  el.grid.innerHTML = '<div class="detail-loading" style="grid-column:1/-1">加载中…</div>';

  try {
    const data = await api(`/api/recipes?${params.toString()}`);
    state.items = data.items;
    state.total = data.total;
    state.page = data.page;
    render();
  } catch (error) {
    el.grid.innerHTML = `<div class="detail-loading" style="grid-column:1/-1">加载失败：${esc(
      error.message,
    )}</div>`;
  }
}

/* ------------------------------------------------------------------ */
/* 渲染                                                                */
/* ------------------------------------------------------------------ */

function render() {
  renderSummary();
  renderGrid();
  renderPagination();
}

function renderSummary() {
  const filters = [];
  if (state.q) filters.push(`搜索「${state.q}」`);
  if (state.tag) filters.push(`标签「${state.tag}」`);

  const rangeStart = state.total === 0 ? 0 : (state.page - 1) * state.pageSize + 1;
  const rangeEnd = Math.min(state.page * state.pageSize, state.total);

  el.resultSummary.innerHTML =
    state.total === 0
      ? '没有匹配的菜谱'
      : `共 <strong>${state.total}</strong> 道菜谱，当前显示第 ${rangeStart}–${rangeEnd} 条`;

  el.activeFilters.innerHTML = filters.map((text) => `<span class="chip">${esc(text)}</span>`).join('');
  el.clearTag.hidden = !state.tag;
  el.searchClear.hidden = !state.q;

  const isEmpty = state.total === 0 && !state.q && !state.tag;
  el.emptyState.hidden = !isEmpty;
  el.grid.hidden = state.total === 0;
}

function cardHtml(recipe) {
  const badges = [];
  if (recipe.ingredients.length) badges.push(`<span class="badge">${recipe.ingredients.length} 种用料</span>`);
  if (recipe.steps.length) badges.push(`<span class="badge">${recipe.steps.length} 步</span>`);

  const cover = recipe.coverImage
    ? `<img src="${imageUrl(recipe.coverImage)}" alt="${esc(recipe.title)}" loading="lazy" />`
    : `<div class="placeholder">${esc((recipe.title || '菜')[0])}</div>`;

  const tags = recipe.tags
    .slice(0, 3)
    .map((tag) => `<span class="card-tag">${esc(tag)}</span>`)
    .join('');

  /* 主料 / 调料统计（卡片顶部一行） */
  const groups = recipe.ingredientGroups || { main: [], seasoning: [] };
  const mainCount = (groups.main || []).length;
  const seasonCount = (groups.seasoning || []).length;
  const hasGroups = mainCount + seasonCount > 0;
  const mainPreview = (groups.main || []).slice(0, 3).map((i) => esc(i.name)).join('、');
  const seasonPreview = (groups.seasoning || []).slice(0, 3).map((i) => esc(i.name)).join('、');
  const ingRow = hasGroups
    ? `<div class="card-ing">
        <span class="card-ing-main" title="${esc((groups.main || []).map((i) => i.name).join('、'))}">
          <span class="ing-ico">🍖</span>主料 ${mainCount}${mainPreview ? ' · ' + mainPreview : ''}
        </span>
        ${seasonCount ? `<span class="card-ing-sep">·</span>
        <span class="card-ing-season" title="${esc((groups.seasoning || []).map((i) => i.name).join('、'))}">
          <span class="ing-ico">🧂</span>调料 ${seasonCount}${seasonPreview ? ' · ' + seasonPreview : ''}
        </span>` : ''}
      </div>`
    : '';

  return `
    <article class="card" data-id="${recipe.id}">
      <div class="card-cover">
        ${cover}
        <div class="card-badges">${badges.join('')}</div>
      </div>
      <div class="card-body">
        ${ingRow}
        <div class="card-title">${esc(recipe.title || '未命名')}</div>
        <div class="card-tags">${tags}</div>
      </div>
    </article>`;
}

function renderGrid() {
  if (!state.items.length) {
    el.grid.innerHTML = '';
    return;
  }
  el.grid.innerHTML = state.items.map(cardHtml).join('');
}

function renderPagination() {
  const pageCount = Math.max(1, Math.ceil(state.total / state.pageSize));
  if (pageCount <= 1) {
    el.pagination.hidden = true;
    el.pagination.innerHTML = '';
    return;
  }
  el.pagination.hidden = false;

  const current = state.page;
  const numbers = new Set([1, pageCount, current, current - 1, current + 1]);
  if (current <= 3) [2, 3, 4].forEach((n) => numbers.add(n));
  if (current >= pageCount - 2) [pageCount - 1, pageCount - 2, pageCount - 3].forEach((n) => numbers.add(n));

  const sorted = [...numbers].filter((n) => n >= 1 && n <= pageCount).sort((a, b) => a - b);

  const parts = [
    `<button class="page-btn" data-page="${current - 1}" ${current === 1 ? 'disabled' : ''}>上一页</button>`,
  ];
  let prev = 0;
  for (const n of sorted) {
    if (prev && n - prev > 1) parts.push('<span class="page-gap">…</span>');
    parts.push(
      `<button class="page-btn${n === current ? ' active' : ''}" data-page="${n}">${n}</button>`,
    );
    prev = n;
  }
  parts.push(
    `<button class="page-btn" data-page="${current + 1}" ${
      current === pageCount ? 'disabled' : ''
    }>下一页</button>`,
  );

  el.pagination.innerHTML = parts.join('');
}

/* ------------------------------------------------------------------ */
/* 待做清单 + 工作模式                                                  */
/* ------------------------------------------------------------------ */

/**
 * 步骤的"主/被动"判定：命中"炖/焖/煮/蒸/烤/煲/卤/焙/烩/熬/煨"等关键词
 * 视为被动——只占锅、不占厨师，炖煮期间厨师可以去做别的菜谱的动手步骤。
 * 命中后用 word-boundary 检查，避免"烤箱"被误判。
 */
const PASSIVE_KEYWORDS = /(炖|焖|煮|蒸|烤|煲|卤|焙|烩|熬|煨|沸)/;
function isPassiveStep(text) {
  if (!text) return false;
  return PASSIVE_KEYWORDS.test(text);
}

/**
 * 多菜谱时间线调度：统筹方法（单厨师 + 多锅并行，事件驱动模拟）。
 *
 * 不再按菜谱整体串行排布——那样前一个菜谱的炖煮窗口会被白白浪费。
 * 改为在"时间轴上同时推进所有菜谱"：
 * - 每个菜谱维护自己的就绪时刻 cursor（上一步完成时间），步骤必须按顺序
 * - 被动步骤（炖/焖/煮等）：一到就绪时刻立即开火，只占锅不占厨师，多锅可同时炖
 * - 主动步骤（动手）：start = max(自己的 cursor, 厨师空闲时刻)，占用唯一厨师
 * - 统筹优先级：厨师空闲时，优先做"完成后能立刻解锁最长炖煮"的步骤
 *   （先把火烧上，炖着的一两个小时里再去忙别的菜——经典统筹法）
 *
 * 返回 { lanes, globalEnd }，lane.steps 按时间顺序、含 { step, start, end, passive }。
 */
function scheduleRecipes(recipes) {
  const recs = recipes.map((recipe, order) => {
    const items = (Array.isArray(recipe.steps) ? recipe.steps : [])
      .map((step) => ({ step, dur: stepMinutes(step) }))
      .filter((it) => it.dur > 0)
      .map((it) => ({ ...it, passive: isPassiveStep(it.step.text || '') }));
    return {
      order,
      items,
      idx: 0,
      cursor: 0,
      lane: {
        recipeId: recipe.id,
        recipeTitle: recipe.title || '未命名',
        coverImage: recipe.coverImage || '',
        servings: recipe.servings || '',
        steps: [],
      },
    };
  });

  let workerCursor = 0;
  let globalEnd = 0;
  const totalSteps = recs.reduce((s, r) => s + r.items.length, 0);
  let done = 0;

  // 做完某菜谱当前步骤后，紧跟着能解锁的被动时长（下一步若是炖煮，先做它）
  const unlockPassive = (r) => {
    const nx = r.items[r.idx + 1];
    return nx && nx.passive ? nx.dur : 0;
  };
  // 该菜谱剩余的被动总时长（长炖煮的菜优先启动）
  const remainPassive = (r) => {
    let sum = 0;
    for (let i = r.idx; i < r.items.length; i++) if (r.items[i].passive) sum += r.items[i].dur;
    return sum;
  };

  while (done < totalSteps) {
    // 1. 被动步骤：菜谱一到就绪时刻立即开火（不占厨师，可与其他菜谱的动手步骤并行）
    for (const r of recs) {
      while (r.idx < r.items.length && r.items[r.idx].passive) {
        const it = r.items[r.idx];
        const end = r.cursor + it.dur;
        r.lane.steps.push({ step: it.step, start: r.cursor, end, passive: true });
        r.cursor = end;
        r.idx++;
        done++;
        if (end > globalEnd) globalEnd = end;
      }
    }

    // 2. 主动步骤：挑一个厨师现在（或最早）能做的
    const candidates = recs.filter((r) => r.idx < r.items.length && !r.items[r.idx].passive);
    if (!candidates.length) break;
    const earliest = Math.min(...candidates.map((r) => Math.max(r.cursor, workerCursor)));
    const ready = candidates.filter((r) => r.cursor <= earliest);
    ready.sort(
      (a, b) =>
        unlockPassive(b) - unlockPassive(a) ||
        remainPassive(b) - remainPassive(a) ||
        a.order - b.order,
    );
    const r = ready[0];
    const it = r.items[r.idx];
    const start = Math.max(r.cursor, workerCursor);
    const end = start + it.dur;
    r.lane.steps.push({ step: it.step, start, end, passive: false });
    r.cursor = end;
    r.idx++;
    done++;
    workerCursor = end;
    if (end > globalEnd) globalEnd = end;
  }

  const lanes = recs.filter((r) => r.lane.steps.length).map((r) => r.lane);
  return { lanes, globalEnd };
}

/** 食材名归一化：去空白 / 标点 / 全角转半角，按"相同原料"聚合。 */
function normIngredientName(name) {
  return String(name || '')
    .toLowerCase()
    .replace(/\u3000/g, '')
    .replace(/[\s，、。；：,.;:()（）【】\[\]\\/·•]/g, '')
    .trim();
}

/**
 * 汇总多个菜谱的主料 / 辅料：
 * - 同一名字出现 N 次，标"× N 份"
 * - 第一次出现的份量作为参考，多个份量不强行叠加（避免信息噪音）
 */
function aggregateIngredients(recipes) {
  const main = new Map();
  const season = new Map();

  for (const r of recipes) {
    const groups = r.ingredientGroups || { main: [], seasoning: [] };
    for (const [target, items] of [
      [main, groups.main || []],
      [season, groups.seasoning || []],
    ]) {
      for (const item of items) {
        const key = normIngredientName(item && item.name);
        if (!key) continue;
        if (!target.has(key)) {
          target.set(key, { name: item.name, amounts: [], recipes: 0 });
        }
        const entry = target.get(key);
        entry.amounts.push(item.amount || '');
        entry.recipes += 1;
      }
    }
  }

  const sortByUsage = (a, b) => b[1].recipes - a[1].recipes || a[0].localeCompare(b[0], 'zh');
  return {
    main: [...main.entries()].sort(sortByUsage).map(([, v]) => v),
    seasoning: [...season.entries()].sort(sortByUsage).map(([, v]) => v),
  };
}

const PLAN_KEY = 'cook_plan_v1';
function getPlan() {
  try {
    const raw = localStorage.getItem(PLAN_KEY);
    const arr = JSON.parse(raw || '[]');
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}
function savePlan(plan) {
  localStorage.setItem(PLAN_KEY, JSON.stringify(plan));
  updatePlanBadge();
}
function addToPlan(recipe) {
  const plan = getPlan();
  const id = String(recipe.id);
  if (plan.some((p) => String(p.id) === id)) return false;
  plan.unshift({
    id: recipe.id,
    title: recipe.title || '',
    coverImage: recipe.coverImage || '',
    servings: recipe.servings || '',
    addedAt: new Date().toISOString(),
  });
  savePlan(plan);
  return true;
}
function removeFromPlan(id) {
  const plan = getPlan().filter((p) => String(p.id) !== String(id));
  savePlan(plan);
  return plan;
}
function clearPlan() {
  savePlan([]);
}
function updatePlanBadge() {
  const plan = getPlan();
  const count = plan.length;
  if (el.planBar) {
    el.planBar.hidden = count === 0;
    if (el.planCount) el.planCount.textContent = String(count);
  }
  if (el.cookPlanCount) el.cookPlanCount.textContent = String(count);
}

/**
 * 详情抽屉里"🔥 待做"按钮：加入清单后简短反馈（按钮变"已加入 ✓"，2 秒后复原），
 * 不强制关闭抽屉，方便用户连续挑菜。
 */
async function onDrawerPlanClick() {
  if (!currentDetailId) return;
  try {
    const recipe = await api(`/api/recipes/${currentDetailId}`);
    const added = addToPlan(recipe);
    if (!added) {
      flashDrawerPlanButton('已在清单里', '✓');
      return;
    }
    flashDrawerPlanButton('已加入清单', '✓');
  } catch (error) {
    window.alert(`加入清单失败：${error.message}`);
  }
}

let drawerPlanFlashTimer = null;
function flashDrawerPlanButton(label, icon) {
  if (!el.drawerPlan) return;
  clearTimeout(drawerPlanFlashTimer);
  el.drawerPlan.dataset.state = 'done';
  el.drawerPlan.innerHTML = `<span style="margin-right:4px">${icon}</span>${esc(label)}`;
  drawerPlanFlashTimer = setTimeout(() => {
    el.drawerPlan.dataset.state = '';
    el.drawerPlan.innerHTML = '🔥 待做';
  }, 1600);
}

function openPlanModal() {
  renderPlanModal();
  el.planModal.hidden = false;
}
function closePlanModal() {
  el.planModal.hidden = true;
}
function renderPlanModal() {
  const plan = getPlan();
  if (!plan.length) {
    el.planList.innerHTML = '<li class="plan-empty">清单是空的，去详情页点「🔥 待做」凑齐几道菜吧。</li>';
    el.planStart.disabled = true;
    return;
  }
  el.planStart.disabled = false;
  el.planList.innerHTML = plan
    .map(
      (p, i) => `
        <li class="plan-row" data-id="${esc(p.id)}">
          <span class="plan-row-no">${esc((p.title || '未命名').slice(0, 1))}</span>
          <span class="plan-row-title">${esc(p.title || '未命名')}</span>
          ${p.servings ? `<span class="plan-row-servings">${esc(p.servings)}</span>` : ''}
          <span class="plan-row-tools">
            <button class="btn btn-ghost plan-row-move" type="button" data-dir="-1" data-id="${esc(p.id)}"
                    title="上移（影响统筹调度顺序）"${i === 0 ? ' disabled' : ''}>↑</button>
            <button class="btn btn-ghost plan-row-move" type="button" data-dir="1" data-id="${esc(p.id)}"
                    title="下移（影响统筹调度顺序）"${i === plan.length - 1 ? ' disabled' : ''}>↓</button>
            <button class="btn btn-ghost btn-danger plan-row-remove" type="button" data-id="${esc(p.id)}">移出</button>
          </span>
        </li>`,
    )
    .join('');
}

/** 清单内移动某道菜的位置（dir = -1 上移 / 1 下移） */
function movePlanItem(id, dir) {
  const plan = getPlan();
  const idx = plan.findIndex((p) => String(p.id) === String(id));
  const next = idx + dir;
  if (idx < 0 || next < 0 || next >= plan.length) return false;
  [plan[idx], plan[next]] = [plan[next], plan[idx]];
  savePlan(plan);
  return true;
}

/**
 * 清单变动后：若正处于工作模式，后台重新拉取 + 调度 + 渲染（不关弹层）。
 * 用序号防止竞态：连点 ↑↓ 时只有最后一次渲染生效。
 */
let cookRefreshSeq = 0;
async function refreshCookModeInBackground() {
  if (!el.cookMode || el.cookMode.hidden) return;
  const plan = getPlan();
  if (!plan.length) {
    exitCookMode();
    return;
  }
  const seq = ++cookRefreshSeq;
  try {
    const recipes = await fetchRecipesByIds(plan.map((p) => p.id));
    if (seq !== cookRefreshSeq || el.cookMode.hidden) return;
    if (!recipes.length) {
      exitCookMode();
      return;
    }
    renderCookMode(recipes);
  } catch {
    /* 忽略，保持上一次渲染 */
  }
}

/** 进入工作模式：拉取所有清单菜谱完整数据，调度并渲染。 */
async function enterCookMode() {
  const plan = getPlan();
  if (!plan.length) {
    window.alert('清单是空的，先加几道菜再来开干。');
    return;
  }
  closePlanModal();
  enterCookLoading();
  try {
    const recipes = await fetchRecipesByIds(plan.map((p) => p.id));
    if (!recipes.length) {
      window.alert('清单里的菜谱都不存在了，请重新挑选。');
      exitCookMode();
      return;
    }
    renderCookMode(recipes);
  } catch (error) {
    window.alert(`进入工作模式失败：${error.message}`);
    exitCookMode();
  }
}

async function fetchRecipesByIds(ids) {
  const out = [];
  for (const id of ids) {
    try {
      const r = await api(`/api/recipes/${encodeURIComponent(id)}`);
      out.push(r);
    } catch (error) {
      console.warn(`拉取菜谱 ${id} 失败：`, error);
    }
  }
  return out;
}

function enterCookLoading() {
  document.body.classList.add('mode-cook');
  el.cookMode.hidden = false;
  completedStepKeys.clear();
  highlightedStepKey = null;
  el.cookTimeline.innerHTML = '<div class="cook-loading">正在调度时间线…</div>';
  if (el.cookOrderStrip) el.cookOrderStrip.innerHTML = '';
  el.cookMainList.innerHTML = '';
  el.cookSeasonList.innerHTML = '';
  el.cookRecipes.innerHTML = '';
  if (el.cookTimelineMeta) el.cookTimelineMeta.textContent = '—';
  if (el.cookSummary) el.cookSummary.textContent = '加载中…';
}

function exitCookMode() {
  document.body.classList.remove('mode-cook');
  el.cookMode.hidden = true;
  el.cookTimeline.innerHTML = '';
  if (el.cookOrderStrip) el.cookOrderStrip.innerHTML = '';
  el.cookMainList.innerHTML = '';
  el.cookSeasonList.innerHTML = '';
  el.cookRecipes.innerHTML = '';
  highlightedStepKey = null;
}

function renderCookMode(recipes) {
  const { lanes, globalEnd } = scheduleRecipes(recipes);
  const { main, seasoning } = aggregateIngredients(recipes);

  if (el.cookSummary) {
    const active = lanes.reduce((s, l) => s + l.steps.filter((x) => !x.passive).length, 0);
    const passive = lanes.reduce((s, l) => s + l.steps.filter((x) => x.passive).length, 0);
    el.cookSummary.textContent = `${recipes.length} 道菜 · 共 ${active} 个动手步骤 · ${passive} 个等待步骤 · 总时长 ${formatMinutes(globalEnd)}`;
  }

  renderCookIngredients(main, el.cookMainList);
  renderCookIngredients(seasoning, el.cookSeasonList);

  renderCookTimeline(lanes, globalEnd);
  renderCookOrder(lanes);
  renderCookRecipes(lanes);
  applyDoneStates(); // 时间线 / 步骤详情在 renderCookOrder 之后才存在，这里再统一同步一次
}

function renderCookIngredients(list, host) {
  if (!host) return;
  if (!list.length) {
    host.innerHTML = '<div class="cook-ing-empty">无</div>';
    return;
  }
  host.innerHTML = list
    .map(
      (item) => `
        <div class="cook-ing-item">
          <span class="cook-ing-name">${esc(item.name)}</span>
          <span class="cook-ing-meta">
            <span class="cook-ing-count">× ${item.recipes} 份</span>
            ${item.amounts[0] ? `<span class="cook-ing-amount">参考：${esc(item.amounts[0])}</span>` : ''}
          </span>
        </div>`,
    )
    .join('');
}

function renderCookTimeline(lanes, globalEnd) {
  if (el.cookTimelineMeta) {
    el.cookTimelineMeta.textContent = globalEnd > 0
      ? `总耗时 ${formatMinutes(globalEnd)} · 统筹调度：炖煮等待时穿插其他菜谱的工序`
      : '没有可用步骤';
  }
  if (!globalEnd || !lanes.length) {
    el.cookTimeline.innerHTML = '<div class="cook-loading">这些菜谱暂未抓到步骤时间，无法生成时间线。</div>';
    return;
  }
  const total = globalEnd;
  const ticks = buildTimeTicks(total);

  const lanesHtml = lanes
    .map((lane) => {
      const blocks = lane.steps
        .map((it) => {
          const left = (it.start / total) * 100;
          const width = Math.max(((it.end - it.start) / total) * 100, 1.5);
          const minutes = Math.round(it.end - it.start);
          const text = (it.step.text || '').replace(/\s+/g, ' ');
          const safeTitle = text.length > 80 ? text.slice(0, 80) + '…' : text;
          return `<div class="cook-bar ${it.passive ? 'passive' : 'active'}"
                       data-rid="${esc(lane.recipeId)}"
                       data-sidx="${esc(it.step.index || '')}"
                       style="left:${left.toFixed(3)}%;width:${width.toFixed(3)}%"
                       title="${esc(`${formatMinutes(it.start)} → ${formatMinutes(it.end)} · ${minutes} 分钟 · ${safeTitle}`)}">
                  <span class="cook-bar-label">${esc(it.step.index)} · ${minutes}′</span>
                </div>`;
        })
        .join('');
      const finish = lane.steps[lane.steps.length - 1].end;
      return `
        <div class="cook-lane" data-rid="${esc(lane.recipeId)}">
          <div class="cook-lane-meta">
            <span class="cook-lane-title">${esc(lane.recipeTitle)}</span>
            ${lane.servings ? `<span class="cook-lane-servings">${esc(lane.servings)}</span>` : ''}
            <span class="cook-lane-dur">${formatMinutes(finish)} 完成</span>
          </div>
          <div class="cook-lane-track">
            ${blocks}
          </div>
        </div>`;
    })
    .join('');

  const axisHtml = `
    <div class="cook-axis">
      <div class="cook-axis-line"></div>
      ${ticks
        .map((t) => `<span class="cook-axis-tick" style="left:${((t / total) * 100).toFixed(3)}%">${esc(formatAxisCompact(t))}</span>`)
        .join('')}
    </div>`;

  el.cookTimeline.innerHTML = axisHtml + `<div class="cook-lanes">${lanesHtml}</div>`;
}

/**
 * 开工顺序卡片（工作模式主内容）：所有菜谱的全部工序按统筹调度时间拉平、
 * 横向排队。每张子卡片展示完整步骤详情：菜谱名、步骤号、时长、描述、图片。
 * 右上角「完成」按钮标注完成状态（绿色高亮），并自动推进到下一张未完成卡片。
 * 中间显示的卡片大、两侧略小（updateOrderCardScales 按离中心距离缩放）。
 */
const completedStepKeys = new Set();

function renderCookOrder(lanes) {
  if (!el.cookOrderStrip) return;
  const items = [];
  lanes.forEach((lane, li) => {
    lane.steps.forEach((it) => items.push({ lane, it, li }));
  });
  items.sort((a, b) => a.it.start - b.it.start || a.li - b.li || a.it.step.index - b.it.step.index);

  el.cookOrderStrip.innerHTML = items
    .map(({ lane, it }) => {
      const minutes = Math.round(it.end - it.start);
      const key = `${lane.recipeId}-${it.step.index || ''}`;
      const done = completedStepKeys.has(key);
      const text = (it.step.text || '').replace(/\s+/g, ' ');
      return `
        <article class="cook-order-chip ${it.passive ? 'passive' : 'active'}${done ? ' done' : ''}"
                 data-rid="${esc(lane.recipeId)}"
                 data-sidx="${esc(it.step.index || '')}"
                 data-key="${esc(key)}">
          <button type="button" class="chip-done-btn" title="标记这一步完成">${done ? '✓ 已完成' : '完成'}</button>
          <header class="chip-head">
            <span class="chip-recipe" title="${esc(lane.recipeTitle)}">${esc(lane.recipeTitle)}</span>
            <span class="chip-step">步骤 ${esc(it.step.index)} · <b class="chip-time">${minutes}′</b></span>
          </header>
          ${it.step.image ? `<img class="chip-img" src="${esc(imageUrl(it.step.image))}" alt="步骤 ${esc(it.step.index)}" loading="lazy" />` : ''}
          <p class="chip-desc">${esc(text)}</p>
          <footer class="chip-range">
            <span class="chip-tag${it.passive ? ' passive' : ''}">${it.passive ? '等待' : '动手'}</span>
            <span>${esc(formatAxisCompact(it.start))} → ${esc(formatAxisCompact(it.end))}</span>
          </footer>
        </article>`;
    })
    .join('');
  applyDoneStates();
  // 初始定位到第一张未完成的卡片并居中
  const first =
    el.cookOrderStrip.querySelector('.cook-order-chip:not(.done)') ||
    el.cookOrderStrip.querySelector('.cook-order-chip');
  if (first) centerOrderCard(first, false);
  updateOrderCardScales();
}

/** 把某张卡片横向滚动到条带中央（不产生页面纵向滚动） */
function centerOrderCard(card, smooth) {
  const strip = el.cookOrderStrip;
  if (!strip || !card) return;
  const sRect = strip.getBoundingClientRect();
  if (!sRect.width) return;
  const cRect = card.getBoundingClientRect();
  // 卡片视觉中心在内容里的位置（rect 受 transform 缩放影响，中心点不受影响）
  const cardCenter = cRect.left - sRect.left + strip.scrollLeft + cRect.width / 2;
  const target = Math.max(0, cardCenter - sRect.width / 2);
  if (smooth) strip.scrollTo({ left: target, behavior: 'smooth' });
  else strip.scrollLeft = target;
}

/** 更新「已完成 x / y」进度提示 */
function updateOrderProgress() {
  if (!el.cookOrderMeta) return;
  const cards = el.cookOrderStrip ? el.cookOrderStrip.querySelectorAll('.cook-order-chip') : [];
  const done = [...cards].filter((c) => c.classList.contains('done')).length;
  el.cookOrderMeta.textContent = !cards.length
    ? '暂无工序'
    : done >= cards.length
      ? `🎉 全部 ${cards.length} 个工序已完成`
      : `已完成 ${done} / ${cards.length} 步 · 点右上角「完成」推进到下一步`;
}

/** 中间大、两侧小：按卡片中心到条带中心的距离设置缩放 */
let orderScaleRaf = 0;
function updateOrderCardScales() {
  const strip = el.cookOrderStrip;
  if (!strip) return;
  const rect = strip.getBoundingClientRect();
  if (!rect.width) return;
  const center = rect.left + rect.width / 2;
  strip.querySelectorAll('.cook-order-chip').forEach((c) => {
    const r = c.getBoundingClientRect();
    const d = Math.abs(r.left + r.width / 2 - center) / rect.width;
    const scale = Math.max(0.78, 1 - d * 0.55);
    c.style.transform = `scale(${scale.toFixed(3)})`;
  });
}

/** 把「已完成」状态统一同步到三处：开工顺序卡片、时间线块、下方步骤详情 */
function applyDoneStates() {
  const mark = (node) => {
    const done = completedStepKeys.has(`${node.dataset.rid}-${node.dataset.sidx}`);
    node.classList.toggle('done', done);
    const btn = node.querySelector('.chip-done-btn');
    if (btn) btn.textContent = done ? '✓ 已完成' : '完成';
  };
  el.cookTimeline?.querySelectorAll('.cook-bar').forEach(mark);
  el.cookRecipes?.querySelectorAll('.cook-step').forEach(mark);
  el.cookOrderStrip?.querySelectorAll('.cook-order-chip').forEach(mark);
  updateOrderProgress();
}

/** 双击开工顺序卡片 → 滚动到下方步骤详情对应条目并闪烁提示 */
function jumpToStepDetail(rid, sidx) {
  const key = `${rid}-${sidx}`;
  const target = el.cookRecipes?.querySelector(`.cook-step[data-key="${CSS.escape(key)}"]`);
  if (!target) return;
  highlightedStepKey = null; // 双击会先触发两次 click，重置后再高亮保证选中态
  highlightCookStep(rid, sidx, { scrollDetail: false });
  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  el.cookRecipes.querySelectorAll('.cook-step.flash').forEach((s) => s.classList.remove('flash'));
  target.classList.add('flash');
  window.setTimeout(() => target.classList.remove('flash'), 1500);
}

/** 点「完成」：标注绿色完成态 → 推进到下一张未完成卡片并联动高亮时间线 */
function completeOrderStep(card) {
  if (!card || card.classList.contains('done')) return;
  completedStepKeys.add(`${card.dataset.rid}-${card.dataset.sidx}`);
  applyDoneStates(); // 时间线块 + 步骤详情同步变绿

  const cards = [...el.cookOrderStrip.querySelectorAll('.cook-order-chip')];
  const next = cards.slice(cards.indexOf(card) + 1).find((c) => !c.classList.contains('done'));
  if (!next) return;
  centerOrderCard(next, true);
  // 联动高亮下一张卡 + 时间线（不把页面拽到下方步骤详情）
  highlightedStepKey = null;
  highlightCookStep(next.dataset.rid, next.dataset.sidx, { scrollDetail: false });
}

/** 时间轴刻度的紧凑格式：0 / 30′ / 1h30 / 2h */
function formatAxisCompact(total) {
  const t = Math.round(total);
  if (t === 0) return '0';
  const h = Math.floor(t / 60);
  const m = t - h * 60;
  if (!h) return `${m}′`;
  return m ? `${h}h${m}` : `${h}h`;
}

/** 在 [0, total] 上挑 4~6 个等距刻度（端点必含），让时间线有参照点。 */
function buildTimeTicks(total) {
  if (total <= 0) return [];
  const targets = [0, total];
  const ideal = 5;
  let step = total / ideal;
  const niceSteps = [1, 2, 5, 10, 15, 20, 30, 60, 90, 120, 180];
  step = niceSteps.find((n) => n >= step) || step;
  if (step <= 0) step = total;
  for (let t = step; t < total; t += step) targets.push(t);
  return [...new Set(targets.map((t) => Math.min(total, Math.round(t))))].sort((a, b) => a - b);
}

function renderCookRecipes(lanes) {
  const html = lanes
    .map((lane) => {
      const stepBlocks = lane.steps
        .map((it) => {
          const dur = Math.round(it.end - it.start);
          const tag = it.passive ? '<span class="step-tag passive">等待</span>' : '<span class="step-tag active">动手</span>';
          return `
            <div class="step-item cook-step" data-rid="${esc(lane.recipeId)}" data-sidx="${esc(it.step.index || '')}" data-key="${esc(`${lane.recipeId}-${it.step.index}`)}">
              <div class="step-no">${esc(it.step.index)}</div>
              <div class="step-content">
                <div class="cook-step-meta">
                  ${tag}
                  <span class="step-time-head">⏱ ${formatStepBadge(dur)}</span>
                  <span class="cook-step-time">${formatMinutes(it.start)} → ${formatMinutes(it.end)}</span>
                </div>
                <p>${highlightStepTime(it.step.text || '')}</p>
                ${it.step.image ? `<img src="${imageUrl(it.step.image)}" alt="步骤 ${esc(it.step.index)}" loading="lazy" />` : ''}
              </div>
            </div>`;
        })
        .join('');
      return `
        <div class="cook-recipe-block" data-rid="${esc(lane.recipeId)}">
          <h3 class="cook-recipe-title">${esc(lane.recipeTitle)}</h3>
          ${lane.coverImage ? `<img class="cook-recipe-cover" src="${imageUrl(lane.coverImage)}" alt="" />` : ''}
          <div class="cook-step-list">${stepBlocks}</div>
        </div>`;
    })
    .join('');
  el.cookRecipes.innerHTML = html || '<p class="cook-loading">没有步骤可显示。</p>';
}

/** 高亮工作模式里点击的时间块 → 开工顺序卡片 + 下方步骤详情，三处联动 */
let highlightedStepKey = null;
function highlightCookStep(rid, sidx, opts) {
  const { scrollDetail = true } = opts || {};
  const key = `${rid}-${sidx}`;
  const fresh = highlightedStepKey !== key;
  el.cookTimeline?.querySelectorAll('.cook-bar').forEach((b) => {
    const bKey = `${b.dataset.rid}-${b.dataset.sidx}`;
    b.classList.toggle('selected', bKey === key && fresh);
  });
  el.cookOrderStrip?.querySelectorAll('.cook-order-chip').forEach((c) => {
    const cKey = `${c.dataset.rid}-${c.dataset.sidx}`;
    c.classList.toggle('selected', cKey === key && fresh);
  });
  el.cookRecipes?.querySelectorAll('.cook-step').forEach((s) => {
    const sKey = `${s.dataset.rid}-${s.dataset.sidx}`;
    s.classList.toggle('selected', sKey === key);
  });
  if (scrollDetail) {
    const target = el.cookRecipes?.querySelector(`.cook-step[data-key="${CSS.escape(key)}"]`);
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }
  const chip = el.cookOrderStrip?.querySelector(
    `.cook-order-chip[data-rid="${CSS.escape(String(rid))}"][data-sidx="${CSS.escape(String(sidx))}"]`,
  );
  if (chip) chip.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
  highlightedStepKey = key;
}

/* ------------------------------------------------------------------ */
/* 详情                                                                */
/* ------------------------------------------------------------------ */

let currentDetailId = null;

async function openDetail(id) {
  currentDetailId = id;
  el.drawer.hidden = false;
  el.drawerBackdrop.hidden = false;
  el.drawerDelete.disabled = true;
  el.drawerBody.innerHTML = '<div class="detail-loading">加载中…</div>';
  el.drawerSource.href = `https://www.xiachufang.com/recipe/${id}/`;

  try {
    const recipe = await api(`/api/recipes/${id}`);
    el.drawerSource.href = recipe.url || el.drawerSource.href;

    const meta = [];
    if (recipe.author) meta.push(`作者：${esc(recipe.author)}`);
    if (recipe.servings) meta.push(esc(recipe.servings));
    if (recipe.madeCount) meta.push(`${esc(recipe.madeCount)} 人做过`);
    if (recipe.favCount) meta.push(`${esc(recipe.favCount)} 收藏`);
    meta.push(`抓取于 ${formatTime(recipe.collectedAt)}`);

    const ingredients = renderIngredientGroups(recipe);

    const steps = recipe.steps.length
      ? recipe.steps.map((step) => renderStep(step)).join('')
      : '<p style="color:var(--muted);font-size:13px">未抓取到步骤信息</p>';

    el.drawerBody.innerHTML = `
      <h2 class="detail-title">${esc(recipe.title || '未命名')}</h2>
      <div class="detail-meta">${meta.map((m) => `<span>${m}</span>`).join('')}</div>
      ${recipe.coverImage ? `<img class="detail-cover" src="${imageUrl(recipe.coverImage)}" alt="" />` : ''}
      ${recipe.description ? `<p class="detail-desc">${esc(recipe.description)}</p>` : ''}
      ${recipe.tags.length ? `<div class="card-tags">${recipe.tags.map((t) => `<span class="card-tag">${esc(t)}</span>`).join('')}</div>` : ''}
      <div class="section-title">用料（${recipe.ingredients.length}）</div>
      ${ingredients}
      ${renderTotalTime(recipe)}
      <div class="section-title">做法（${recipe.steps.length} 步）</div>
      ${steps}
      ${recipe.tips ? `<div class="section-title">小贴士</div><p class="detail-tips">${esc(recipe.tips)}</p>` : ''}
    `;
    el.drawerBody.scrollTop = 0;
    el.drawerDelete.disabled = false;
  } catch (error) {
    el.drawerBody.innerHTML = `<div class="detail-loading">加载失败：${esc(error.message)}</div>`;
  }
}

/**
 * 步骤用时启发式估算：动词 → 分钟数。按关键词优先级匹配。
 * 规则都没命中时返回 1（兜底），保证总时长能覆盖到每一步。
 */
const STEP_TIME_RULES = [
  [/(烤箱|烘烤|烤制|烤至|烤好|烤出|烤到)/i, 25],
  [/(慢炖|炖煮|小火炖|小火煲)/i, 45],
  [/(焖煮|焖制|焖)/i, 30],
  [/(大火煮|中火煮|小火煮|水煮|汆|氽|白灼)/i, 10],
  [/(蒸制|蒸熟|蒸至|上锅蒸|隔水蒸)/i, 18],
  [/(油炸|复炸|炸至|炸到|煎炸)/i, 6],
  [/(煎制|煎至|煎到|煎)/i, 5],
  [/(煸炒|翻炒|爆炒|大火爆炒|清炒)/i, 3],
  [/(腌制|腌渍|泡发|浸泡)/i, 30],
  [/(醒发|发酵|饧发|发面)/i, 60],
  [/(冷藏|冷冻|冰镇)/i, 30],
  [/(切丝|切片|切块|切碎|切丁|剁|拍碎|拍扁)/i, 2],
  [/(搅拌|拌匀|混合|搅匀|揉)/i, 2],
  [/(热锅|起锅|烧热|预热)/i, 2],
  [/(撒上|摆盘|装盘|出锅|盛出|淋上)/i, 1],
  [/(煮|烧|烫)/i, 8],
  // 兜底专项：削皮类、切类
  [/(削皮|削)/i, 5],
  [/切/i, 2],
];

function estimateStepMinutes(text) {
  if (!text) return 0;
  for (const [re, m] of STEP_TIME_RULES) {
    if (re.test(text)) return m;
  }
  return 1;
}

/** 检测文本里是否包含数字 + 时间单位。\b 在中文环境失效，所以不用 \b。 */
const TIME_PATTERN = /(\d+(?:\.\d+)?\s*(?:秒|分钟|个小时|半小时|小时|hour|hours|minute|minutes|sec|secs|min|mins|hr|hrs|h|min))/gi;

/** 中文量词式时间：一小时、半小时、几小时、几分钟、一刻钟、几秒、二十五分钟 */
const CN_NUM = { 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9, 十: 10, 半: 0.5, 几: 2 };
function cnValue(s) {
  if (CN_NUM[s] !== undefined) return CN_NUM[s];
  if (s.length === 2 && s[1] === '十') return (CN_NUM[s[0]] || 0) * 10;
  if (s.length === 3 && s[1] === '十') return (CN_NUM[s[0]] || 0) * 10 + (CN_NUM[s[2]] || 0);
  return 0;
}
const CN_UNIT_MIN = { 小时: 60, 个小时: 60, 分钟: 1, 刻钟: 15, 秒: 1 / 60 };
const CN_TIME_RE = /((?:[一二两三四五六七八九]十[一二三四五六七八九]?|[一二三四五六七八九]十|[一二两三四五六七八九十半几]))(?:个)?(小时|分钟|刻钟|秒)/g;
const CN_TIME_TEST = /[一二两三四五六七八九十半几](?:个)?(?:小时|分钟|刻钟|秒)/;

function highlightStepTime(text) {
  if (!text) return '';
  const safe = esc(text);
  return safe
    .replace(TIME_PATTERN, (m) => `<b class="step-time-inline">${m}</b>`)
    .replace(CN_TIME_RE, (m) => `<b class="step-time-inline">${m}</b>`);
}

function hasExplicitTime(text) {
  if (!text) return false;
  // 注意：TIME_PATTERN 是 /gi，连续 test 会改变 lastIndex。每次前重置。
  TIME_PATTERN.lastIndex = 0;
  return TIME_PATTERN.test(text) || CN_TIME_TEST.test(text);
}

/**
 * 渲染单步：把 stepMinutes 算出的"总用时"放在步骤号右侧。
 * 文本中的每个时间片段仍加粗；多个时间会自动叠加为一个汇总（如"半小时+15分钟+10分钟"=55 分钟）。
 */
function renderStep(step) {
  const text = step.text || '';
  const image = step.image
    ? `<img src="${imageUrl(step.image)}" alt="步骤 ${step.index}" loading="lazy" />`
    : '';
  const minutes = stepMinutes(step);
  const headBadge = minutes
    ? `<span class="step-time-head" title="把步骤里所有时间片段相加；没有时间时按动作关键词估算">⏱ ${formatStepBadge(minutes)}</span>`
    : '';
  const para = text ? `<p>${highlightStepTime(text)}</p>` : '';
  return `
        <div class="step-item">
          <div class="step-no">${step.index}</div>
          <div class="step-content">
            ${headBadge}
            ${para}
            ${image}
          </div>
        </div>`;
}

/** 把分钟数格式化成"X 分钟" / "X 小时 Y 分钟" */
function formatStepBadge(min) {
  const t = Math.round(min);
  if (t < 60) return `${t} 分钟`;
  const h = Math.floor(t / 60);
  const m = t - h * 60;
  return m ? `${h} 小时 ${m} 分钟` : `${h} 小时`;
}

/** 把文本里的时间描述全部解析成"分钟"。识别 X 小时 / X 分钟 / X 秒 / 中文量词，全部叠加。 */
function parseTimeToMinutes(text) {
  if (!text) return 0;
  let minutes = 0;
  let matched = false;

  /**
   * 边界判断：数字+单位后面若紧跟 ASCII 英文字母，则认为是别的单位（ml / kg / mg ...），
   * 而不是时长，跳过本次匹配。
   */
  const isBoundary = (m) => {
    const next = text.charAt(m.index + m[0].length);
    if (!next) return true; // 文本末尾
    if (/[a-zA-Z]/.test(next)) return false;
    return true;
  };

  // 阿拉伯数字 + 单位（不依赖 \b，中文环境 \b 失效）。用 matchAll 拿所有匹配并叠加。
  const hRe = /(\d+(?:\.\d+)?)\s*(?:小时|个小时|hour|hours|hr|hrs|h)/gi;
  for (const m of text.matchAll(hRe)) {
    if (isBoundary(m)) { minutes += parseFloat(m[1]) * 60; matched = true; }
  }
  const mRe = /(\d+(?:\.\d+)?)\s*(?:分钟|minute|minutes|min|mins|m)/gi;
  for (const m of text.matchAll(mRe)) {
    if (isBoundary(m)) { minutes += parseFloat(m[1]); matched = true; }
  }
  const sRe = /(\d+(?:\.\d+)?)\s*(?:秒|sec|secs|second|seconds)/gi;
  for (const m of text.matchAll(sRe)) {
    if (isBoundary(m)) { minutes += parseFloat(m[1]) / 60; matched = true; }
  }

  // 中文量词：一小时 / 两小时 / 半小时 / 一刻钟 / 几分钟 / 几秒 / 二十五分钟 等
  const re = new RegExp(CN_TIME_RE.source, 'g');
  let cn;
  while ((cn = re.exec(text)) !== null) {
    const n = cnValue(cn[1]);
    const u = cn[2];
    if (n && CN_UNIT_MIN[u] !== undefined) {
      minutes += n * CN_UNIT_MIN[u];
      matched = true;
    }
  }

  return matched ? minutes : 0;
}

/** 单步分钟数：显式时间优先；否则用动词估算；都没有时视为 0 不计 */
function stepMinutes(step) {
  const text = step.text || '';
  if (hasExplicitTime(text)) return parseTimeToMinutes(text);
  return estimateStepMinutes(text);
}

function formatMinutes(total) {
  const t = Math.round(total);
  if (t < 60) return `${t} 分钟`;
  const h = Math.floor(t / 60);
  const m = t - h * 60;
  return m ? `${h} 小时 ${m} 分钟` : `${h} 小时`;
}

function renderTotalTime(recipe) {
  const steps = (recipe && recipe.steps) || [];
  if (!steps.length) return '';
  let total = 0;
  let counted = 0;
  for (const s of steps) {
    const m = stepMinutes(s);
    if (m > 0) { total += m; counted++; }
  }
  if (!total) return '';
  const note = counted < steps.length
    ? `<span class="total-time-note">（已合计 ${counted}/${steps.length} 步）</span>`
    : '';
  return `
      <div class="total-time">
        <span class="total-time-icon">⏱️</span>
        预计总时长 <b>${formatMinutes(total)}</b>
        ${note}
      </div>`;
}

/**
 * 详情页用料分主料/辅料两组。
 * 优先用后端返回的真实分组（main / seasoning）；都为空就降级为单个"全部用料"清单。
 */
function renderIngredientGroups(recipe) {
  const items = (recipe && recipe.ingredients) || [];
  if (!items.length) {
    return '<p style="color:var(--muted);font-size:13px">未抓取到用料信息</p>';
  }

  const groups = (recipe && recipe.ingredientGroups) || {};
  const main = Array.isArray(groups.main) ? groups.main : [];
  const seasoning = Array.isArray(groups.seasoning) ? groups.seasoning : [];

  /* 兜底：老数据 / API 没带分组时，按主料 + 调料空白降级为单组（沿用旧的平面列表） */
  if (!main.length && !seasoning.length) {
    const flat = items
      .map(
        (item) =>
          `<div class="ing-item"><span class="ing-name">${esc(item.name)}</span><span class="ing-amount">${esc(
            item.amount || '',
          )}</span></div>`,
      )
      .join('');
    return `
      <div class="ing-section">
        <div class="ing-group-head">
          <span class="ing-group-title">用料</span>
          <span class="ing-group-count">${items.length} 项</span>
        </div>
        <div class="ing-list">${flat}</div>
      </div>`;
  }

  const renderList = (list) =>
    list
      .map(
        (item) =>
          `<div class="ing-item"><span class="ing-name">${esc(item.name)}</span><span class="ing-amount">${esc(
            item.amount || '',
          )}</span></div>`,
      )
      .join('');

  return `
    <div class="ing-section">
      <div class="ing-group-head ing-group-head-main">
        <span class="ing-group-title"><span class="ing-ico">🍖</span>主料（${main.length}）</span>
      </div>
      ${main.length ? `<div class="ing-list ing-list-main">${renderList(main)}</div>` : '<p class="ing-empty">无</p>'}
    </div>
    <div class="ing-section">
      <div class="ing-group-head ing-group-head-season">
        <span class="ing-group-title"><span class="ing-ico">🧂</span>辅料（${seasoning.length}）</span>
      </div>
      ${seasoning.length ? `<div class="ing-list ing-list-season">${renderList(seasoning)}</div>` : '<p class="ing-empty">无</p>'}
    </div>`;
}

function closeDrawer() {
  el.drawer.hidden = true;
  el.drawerBackdrop.hidden = true;
}

/* ------------------------------------------------------------------ */
/* 任务与日志                                                          */
/* ------------------------------------------------------------------ */

let jobActive = false;

function appendLog(text) {
  const atBottom = el.jobLog.scrollHeight - el.jobLog.scrollTop - el.jobLog.clientHeight < 40;
  el.jobLog.textContent += `${text}\n`;
  if (atBottom) el.jobLog.scrollTop = el.jobLog.scrollHeight;
}

function setJobState(status, title) {
  el.jobTitle.textContent = title;
  el.jobStatusDot.className = `dot ${
    status === 'running' ? '' : status === 'done' ? 'done' : 'failed'
  }`;
  el.jobPanel.dataset.status = status;
  jobActive = status === 'running';
  el.jobCancel.disabled = !jobActive;
  el.btnScrape.disabled = jobActive;
  el.btnLogin.disabled = jobActive;
  el.btnImages.disabled = jobActive;
}

/** 把任务面板显示出来并展开 —— 仅用于「正在跑任务」的场景。 */
function showJobPanel() {
  el.jobPanel.hidden = false;
  el.jobPanel.classList.remove('collapsed');
  el.jobToggle.textContent = '收起';
}

/** 页面初始化时显示上次已完成的任务，但默认收起（窄提示条）。 */
function showFinishedJobCollapsed(status) {
  el.jobPanel.hidden = false;
  el.jobPanel.classList.add('collapsed');
  el.jobToggle.textContent = '展开';
  setJobState(status, '任务已结束');
}

function bindJobStream() {
  const source = new EventSource('/api/jobs/stream');

  source.onmessage = (message) => {
    let event;
    try {
      event = JSON.parse(message.data);
    } catch {
      return;
    }

    switch (event.type) {
      case 'snapshot':
        if (event.logs && event.logs.length) el.jobLog.textContent = `${event.logs.join('\n')}\n`;
        if (event.job) {
          if (event.job.status === 'running') {
            showJobPanel();
            setJobState('running', jobTitle(event.job.kind));
          } else {
            // 已结束的任务只更新标题/状态点，不强制展开
            setJobState(event.job.status === 'done' ? 'done' : 'failed', '任务已结束');
          }
        }
        break;

      case 'log':
        appendLog(event.message);
        break;

      case 'job-started':
        el.jobLog.textContent = '';
        showJobPanel();
        setJobState('running', jobTitle(event.job.kind));
        break;

      case 'login-required':
        el.jobStatusDot.className = 'dot';
        appendLog('>>> 请在弹出的浏览器窗口中完成手动登录 <<<');
        el.jobProgress.textContent = '等待手动登录…';
        break;

      case 'start':
        el.jobProgress.textContent = `源：${event.sourceUrl}`;
        break;

      case 'page':
        el.jobProgress.textContent = `第 ${event.page} 页 · 已收集 ${event.total} 个链接`;
        break;

      case 'collected':
        el.jobProgress.textContent = `共 ${event.total} 个菜谱，计划抓取 ${event.planned} 个`;
        break;

      case 'recipe': {
        const statusText =
          event.status === 'skipped' ? '已存在跳过' : event.status === 'failed' ? '失败' : '完成';
        const imageText = event.images ? ` · 图片 ${event.images}` : '';
        el.jobProgress.textContent = `${event.index}/${event.total} · ${event.title || event.id} · ${statusText}${imageText}`;
        break;
      }

      case 'done':
        el.jobProgress.textContent = `完成：新增 ${event.stats.added}，跳过 ${event.stats.skipped}，失败 ${event.stats.failed}`;
        break;

      case 'error':
        appendLog(`!! 错误：${event.message}`);
        break;

      case 'job-finished':
        setJobState(event.status === 'done' ? 'done' : 'failed', '任务已结束');
        // 保留用户当前的展开/收起状态
        loadStats();
        loadTags();
        loadRecipes();
        break;

      default:
        break;
    }
  };

  source.onerror = () => {
    /* EventSource 会自动重连 */
  };
}

/* ------------------------------------------------------------------ */
/* 事件绑定                                                            */
/* ------------------------------------------------------------------ */

function bindEvents() {
  const runSearch = debounce(() => {
    state.page = 1;
    loadRecipes();
  }, 280);

  el.searchInput.addEventListener('input', (event) => {
    state.q = event.target.value.trim();
    runSearch();
  });

  el.searchClear.addEventListener('click', () => {
    el.searchInput.value = '';
    state.q = '';
    state.page = 1;
    loadRecipes();
  });

  el.sortSelect.addEventListener('change', (event) => {
    state.sort = event.target.value;
    state.page = 1;
    if (state.sort === 'random') state.order = 'desc';
    loadRecipes();
  });

  el.orderToggle.addEventListener('click', () => {
    state.order = state.order === 'asc' ? 'desc' : 'asc';
    el.orderLabel.textContent = state.order === 'asc' ? '升序' : '降序';
    state.page = 1;
    loadRecipes();
  });

  el.pageSizeSelect.addEventListener('change', (event) => {
    state.pageSize = Number(event.target.value);
    state.page = 1;
    loadRecipes();
  });

  el.tagList.addEventListener('click', (event) => {
    const button = event.target.closest('.tag[data-tag]');
    if (!button) return;
    const tag = button.dataset.tag;
    state.tag = state.tag === tag ? '' : tag;
    state.page = 1;
    loadTags();
    loadRecipes();
  });

  el.clearTag.addEventListener('click', () => {
    state.tag = '';
    state.page = 1;
    loadTags();
    loadRecipes();
  });

  el.tagToggle.addEventListener('click', () => {
    el.tagList.dataset.expanded = el.tagList.dataset.expanded === 'true' ? 'false' : 'true';
    el.tagToggle.textContent = el.tagList.dataset.expanded === 'true' ? '收起 ▴' : '展开 ▾';
  });

  el.grid.addEventListener('click', (event) => {
    const card = event.target.closest('.card[data-id]');
    if (card) openDetail(card.dataset.id);
  });

  el.pagination.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-page]');
    if (!button || button.disabled) return;
    const page = Number(button.dataset.page);
    if (page < 1) return;
    state.page = page;
    loadRecipes();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  });

  el.drawerClose.addEventListener('click', closeDrawer);
  el.drawerBackdrop.addEventListener('click', closeDrawer);

  el.drawerDelete.addEventListener('click', async () => {
    if (!currentDetailId) return;
    if (!window.confirm('确定要把这道菜谱从本地库中删除吗？\n（封面图和步骤图也会一并删除）')) return;
    try {
      await api(`/api/recipes/${currentDetailId}`, { method: 'DELETE' });
      closeDrawer();
      await Promise.all([loadStats(), loadTags()]);
      await loadRecipes();
    } catch (error) {
      window.alert(`删除失败：${error.message}`);
    }
  });

  el.drawerTouch.addEventListener('click', async () => {
    if (!currentDetailId) return;
    try {
      const result = await api(`/api/recipes/${currentDetailId}/touch`, { method: 'POST' });
      closeDrawer();
      // 默认 / 当前排序是更新时间时直接回到第一页让该菜谱浮现；
      // 其他排序下也刷新一次保证本地状态一致。
      if (state.sort === 'updated') state.page = 1;
      await Promise.all([loadStats(), loadRecipes()]);
      // 提示一下
      if (result && result.updatedAt) {
        const stamp = new Date(result.updatedAt).toLocaleString('zh-CN', { hour12: false });
        window.alert(`已把更新时间刷新到 ${stamp}，菜谱已置顶到首位。`);
      }
    } catch (error) {
      window.alert(`刷新失败：${error.message}`);
    }
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      closeDrawer();
      el.scrapeModal.hidden = true;
    }
    if (event.key === '/' && document.activeElement !== el.searchInput) {
      event.preventDefault();
      el.searchInput.focus();
    }
  });

  el.btnLogin.addEventListener('click', async () => {
    try {
      el.jobLog.textContent = '';
      await api('/api/jobs/login', { method: 'POST', body: JSON.stringify({ timeout: 600 }) });
      setJobState('running', '登录下厨房');
      appendLog('已打开浏览器窗口，请手动完成登录…');
    } catch (error) {
      window.alert(error.message);
    }
  });

  el.btnScrape.addEventListener('click', () => {
    el.scrapeModal.hidden = false;
    loadSessionHint();
  });

  el.scrapeCancel.addEventListener('click', () => {
    el.scrapeModal.hidden = true;
  });

  el.scrapeConfirm.addEventListener('click', async () => {
    const button = el.scrapeConfirm;
    button.disabled = true;
    try {
      // 注意：参数拼装也放在 try 里，任何异常都要弹出来，避免“点了没反应”
      const withImages = el.optImages.checked;
      const body = {
        ids: el.optIds.value.trim(),
        delay: el.optDelay.value ? Number(el.optDelay.value) : undefined,
        force: el.optForce.checked,
        debug: el.optDebug.checked,
        noImages: !withImages,
        imageSize: withImages ? Number(el.optImageSize.value || 0) : 0,
      };
      if (!body.ids) {
        window.alert('请至少输入一个菜谱 ID 或 URL。');
        return;
      }
      el.jobLog.textContent = '';
      await api('/api/jobs/scrape', { method: 'POST', body: JSON.stringify(body) });
      el.scrapeModal.hidden = true;
      showJobPanel();
      setJobState('running', '抓取菜谱');
    } catch (error) {
      window.alert(`启动抓取失败：${error.message}`);
    } finally {
      button.disabled = false;
    }
  });

  el.btnImages.addEventListener('click', async () => {
    const button = el.btnImages;
    button.disabled = true;
    try {
      el.jobLog.textContent = '';
      await api('/api/jobs/images', {
        method: 'POST',
        body: JSON.stringify({ size: Number(el.optImageSize.value || 0) }),
      });
      setJobState('running', '补抓图片');
    } catch (error) {
      window.alert(`启动补抓失败：${error.message}`);
    } finally {
      button.disabled = false;
    }
  });

  el.jobCancel.addEventListener('click', async () => {
    try {
      await api('/api/jobs/cancel', { method: 'POST' });
    } catch (error) {
      window.alert(error.message);
    }
  });

  el.jobToggle.addEventListener('click', () => {
    const collapsed = el.jobPanel.classList.toggle('collapsed');
    el.jobToggle.textContent = collapsed ? '展开' : '收起';
  });

  /* ---- 待做清单 + 工作模式 ---- */

  el.drawerPlan?.addEventListener('click', onDrawerPlanClick);

  el.btnPlanClear?.addEventListener('click', () => {
    if (!getPlan().length) return;
    if (!window.confirm('确定清空待做清单？')) return;
    clearPlan();
  });

  el.btnCookStart?.addEventListener('click', enterCookMode);

  el.cookPlanManage?.addEventListener('click', openPlanModal);

  el.planCancel?.addEventListener('click', closePlanModal);

  el.planClearAll?.addEventListener('click', () => {
    if (!getPlan().length) return;
    if (!window.confirm('确定清空待做清单？')) return;
    clearPlan();
    renderPlanModal();
    if (!el.cookMode.hidden) exitCookMode();
  });

  el.planStart?.addEventListener('click', enterCookMode);

  el.cookBack?.addEventListener('click', exitCookMode);

  /* 清单里点"↑↓ 调整顺序" / "移出"：工作模式下实时刷新调度 */
  el.planList?.addEventListener('click', (event) => {
    const move = event.target.closest('.plan-row-move[data-id]');
    if (move) {
      if (movePlanItem(move.dataset.id, Number(move.dataset.dir))) {
        renderPlanModal();
        refreshCookModeInBackground();
      }
      return;
    }
    const btn = event.target.closest('.plan-row-remove[data-id]');
    if (!btn) return;
    removeFromPlan(btn.dataset.id);
    renderPlanModal();
    refreshCookModeInBackground();
  });

  /* 开工顺序卡片：右上角「完成」推进下一步；点卡片本体 → 时间线高亮并居中 */
  el.cookOrderStrip?.addEventListener('click', (event) => {
    const doneBtn = event.target.closest('.chip-done-btn');
    if (doneBtn) {
      completeOrderStep(doneBtn.closest('.cook-order-chip'));
      return;
    }
    const chip = event.target.closest('.cook-order-chip[data-rid][data-sidx]');
    if (!chip) return;
    highlightCookStep(chip.dataset.rid, chip.dataset.sidx);
  });

  /* 双击开工顺序卡片：滚动到下方「全部步骤详情」里的对应条目并闪烁定位 */
  el.cookOrderStrip?.addEventListener('dblclick', (event) => {
    const chip = event.target.closest('.cook-order-chip[data-rid][data-sidx]');
    if (!chip) return;
    jumpToStepDetail(chip.dataset.rid, chip.dataset.sidx);
  });

  /* 滚动时保持「中间大、两侧小」的缩放效果（rAF 节流） */
  el.cookOrderStrip?.addEventListener(
    'scroll',
    () => {
      if (orderScaleRaf) return;
      orderScaleRaf = requestAnimationFrame(() => {
        orderScaleRaf = 0;
        updateOrderCardScales();
      });
    },
    { passive: true },
  );
  window.addEventListener('resize', updateOrderCardScales);

  /* 时间线点击：高亮步骤并定位 */
  el.cookTimeline?.addEventListener('click', (event) => {
    const bar = event.target.closest('.cook-bar[data-rid][data-sidx]');
    if (!bar) return;
    highlightCookStep(bar.dataset.rid, bar.dataset.sidx);
  });

  /* 下方步骤列表点击：同步高亮时间块 */
  el.cookRecipes?.addEventListener('click', (event) => {
    const step = event.target.closest('.cook-step[data-rid][data-sidx]');
    if (!step) return;
    highlightCookStep(step.dataset.rid, step.dataset.sidx);
  });

  /* 关闭工作模式的快捷键：Esc（详情 drawer 优先） */
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && document.body.classList.contains('mode-cook')) {
      exitCookMode();
    }
  });
}

/* ------------------------------------------------------------------ */
/* 启动                                                                */
/* ------------------------------------------------------------------ */

async function init() {
  bindEvents();
  bindJobStream();
  updatePlanBadge();
  await Promise.all([loadStats(), loadTags()]);
  await loadRecipes();

  try {
    const { job } = await api('/api/jobs/current');
    if (job) {
      if (job.status === 'running') {
        showJobPanel();
        setJobState('running', jobTitle(job.kind));
      } else if (job.status === 'done' || job.status === 'failed') {
        // 上次任务已结束：默认显示+收起窄提示条，由用户点「展开」看日志
        showFinishedJobCollapsed(job.status === 'done' ? 'done' : 'failed');
      }
    }
  } catch {
    /* ignore */
  }
}

init();
