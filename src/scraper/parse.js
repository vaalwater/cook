'use strict';

/**
 * 本文件里的函数都会通过 page.evaluate() 丢进浏览器执行，
 * 因此每个函数必须是「自包含」的：不能引用外部作用域的变量。
 */

const RECIPE_HREF_RE = /\/recipe\/(\d+)/;
const RECIPE_URL_RE = /^https?:\/\/(?:www\.)?xiachufang\.com\/recipe\/(\d+)/i;

function parseRecipeId(url) {
  if (url == null) return null;
  const match = String(url).match(RECIPE_HREF_RE);
  return match ? match[1] : null;
}

function isRecipeUrl(url) {
  return RECIPE_URL_RE.test(String(url || ''));
}

/* ------------------------------------------------------------------ */
/* 合集 / 收藏列表页                                                    */
/* ------------------------------------------------------------------ */

/**
 * 在集合页里抽出菜谱条目，并判断是否存在下一页。
 * @param {{pageNo:number}} ctx
 */
function extractListInPage(ctx) {
  const pageNo = (ctx && ctx.pageNo) || 1;
  const norm = (s) => (s || '').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim();
  const abs = (u) => {
    if (!u) return '';
    try { return new URL(u, document.baseURI).href; } catch { return ''; }
  };

  const CONTAINERS = [
    '.normal-recipe-list',
    '.recipe-list',
    '.collect-list',
    '.recipe-collect-list',
    '.cook-collect-list',
    '.cook-list',
    '.recipe-collection-list',
  ];

  let scope = null;
  let scoped = '';
  for (const sel of CONTAINERS) {
    const el = document.querySelector(sel);
    if (el && el.querySelectorAll('a[href*="/recipe/"]').length) {
      scope = el;
      scoped = sel;
      break;
    }
  }
  if (!scope) scope = document;

  const items = [];
  const seen = new Set();
  for (const anchor of scope.querySelectorAll('a[href*="/recipe/"]')) {
    const href = anchor.getAttribute('href') || '';
    const match = href.match(/\/recipe\/(\d+)/);
    if (!match) continue;
    const id = match[1];
    if (seen.has(id)) continue;
    seen.add(id);

    const scope2 = anchor.closest('li, .item, .recipe, .recipe-item, .collect-item') || anchor;
    const img = anchor.querySelector('img') || scope2.querySelector('img');
    const titleEl =
      anchor.querySelector('[class*="name"], [class*="title"], h3, h4') ||
      scope2.querySelector('[class*="name"], [class*="title"], h3, h4');

    const title = norm(
      anchor.getAttribute('title') ||
        titleEl?.textContent ||
        img?.getAttribute('alt') ||
        anchor.textContent,
    );

    const cover = abs(
      img?.getAttribute('data-src') || img?.getAttribute('src') || img?.getAttribute('data-original'),
    );

    const cardText = norm(scope2.textContent).slice(0, 200);

    items.push({ id, url: abs(href), title, cover, cardText });
  }

  // 下一页判断
  const nextPattern = new RegExp('[?&]page=' + (pageNo + 1) + '(?:&|$)');
  let hasNext = false;
  for (const anchor of document.querySelectorAll('a[href*="page="]')) {
    const href = anchor.getAttribute('href') || '';
    if (nextPattern.test(href) && !anchor.classList.contains('disabled')) {
      hasNext = true;
      break;
    }
  }
  if (!hasNext) {
    const candidates = document.querySelectorAll('.pagination a, .pager a, a.next, .next_page');
    for (const el of candidates) {
      const label = norm(el.textContent);
      const cls = el.className || '';
      if (
        (/下一页|下页|next/i.test(label) || /next/i.test(String(cls))) &&
        !/disabled/i.test(String(cls)) &&
        !el.hasAttribute('disabled')
      ) {
        hasNext = true;
        break;
      }
    }
  }

  return {
    items,
    hasNext,
    scoped: scoped || 'document',
    totalText: norm(document.querySelector('.page-title, .cook-title, h1')?.textContent),
  };
}

/* ------------------------------------------------------------------ */
/* 菜谱详情页                                                          */
/* ------------------------------------------------------------------ */

function extractRecipeInPage(ctx) {
  const norm = (s) => (s || '').replace(/\u00a0/g, ' ').replace(/\s+/g, ' ').trim();
  const abs = (u) => {
    if (!u) return '';
    try { return new URL(u, document.baseURI).href; } catch { return ''; }
  };
  const pick = (...selectors) => {
    for (const sel of selectors) {
      let el = null;
      try { el = document.querySelector(sel); } catch { el = null; }
      if (el) return el;
    }
    return null;
  };
  const pickText = (...selectors) => norm(pick(...selectors)?.textContent);
  const metaContent = (sel) => document.querySelector(sel)?.getAttribute('content') || '';
  const clean = (url) => {
    if (!url) return '';
    // 下厨房图片常用 /_..._ 缩放后缀，去掉拿到原图
    return abs(url.split('?')[0]);
  };

  const warnings = [];

  /* 标题 */
  let title = pickText('h1.page-title', '.recipe-show h1', '.recipe-title h1', 'h1');
  if (!title) {
    title = metaContent('meta[property="og:title"]') || document.title;
    warnings.push('title:fallback-meta');
  }
  title = norm(title)
    .replace(/\s*[-–|]\s*下厨房.*$/, '')
    .replace(/的做法[_—\-\s]*$/, '')
    .trim();

  /* 简介 */
  let description = pickText('.recipe-show .desc', '.recipe-desc', '.desc', '.intro');
  if (!description) description = norm(metaContent('meta[name="description"]'));

  /* 封面 */
  const coverEl = pick(
    '.recipe-show .cover img',
    '.cover img',
    '.recipe-cover img',
    '.main-pic img',
    'img.recipe-cover',
  );
  const coverImage = clean(
    coverEl?.getAttribute('data-src') ||
      coverEl?.getAttribute('src') ||
      metaContent('meta[property="og:image"]'),
  );

  /* 作者 */
  const author = pickText(
    '.recipe-author a',
    '.author a',
    '.recipe-owner a',
    '.user-name',
    'a[href*="/user/"]',
  );

  /* 份量 */
  const servings = pickText('.recipe-servings', '.servings', '.recipe-show .servings');

  /* 用料 */
  const ingredients = [];
  const ingredientGroups = { main: [], seasoning: [] };
  const ingRoot = pick('.ings', '.recipe-ingredients', '.ingredients', '.recipe-ingredient-list');
  if (ingRoot) {
    /* 找出所有分组标题节点（"主料"/"辅料"/"配料"/"调料"/"食材" 等） */
    const GROUP_LABEL_RE = /^(主料|辅料|配料|调料|调味料|食材|主食材|主要食材)$/;
    const LABEL_TO_GROUP = { '主料': 'main', '食材': 'main', '主食材': 'main', '主要食材': 'main',
                              '辅料': 'seasoning', '配料': 'seasoning', '调料': 'seasoning', '调味料': 'seasoning' };
    const groupHeaders = [];
    for (const el of ingRoot.querySelectorAll('h1,h2,h3,h4,h5,h6,legend,b,strong,div,span,p')) {
      if (el.children.length > 0) continue;          // 必须是叶子节点
      const t = norm(el.textContent).trim();
      if (GROUP_LABEL_RE.test(t)) groupHeaders.push({ el, group: LABEL_TO_GROUP[t] });
    }

    const rows = ingRoot.querySelectorAll('tr, .ingredient, .ingredients-item, li');
    const nodes = rows.length ? rows : ingRoot.children;
    for (const row of nodes) {
      if (!row || row.nodeType !== 1) continue;
      if (row.classList && /header|title|category/i.test(row.className)) continue;
      // 跳过作为分组标题的节点自身
      if (groupHeaders.some((h) => h.el === row)) continue;

      const nameEl = row.querySelector('.name, .ing-name, .ingredient-name, dt, b, strong');
      const amountEl = row.querySelector(
        '.unit, .amount, .ingredient-amount, .quantity, dd',
      );

      let name = '';
      let amount = '';
      if (nameEl) {
        name = norm(nameEl.textContent);
        amount = norm(amountEl?.textContent);
      } else {
        const cells = row.querySelectorAll('td, span, div');
        if (cells.length >= 2) {
          name = norm(cells[0].textContent);
          amount = norm(cells[1].textContent);
        } else {
          name = norm(row.textContent);
        }
      }
      if (!name) continue;
      // 丢弃"用量较少"等无效噪音行
      if (/^(用料|主料|辅料|配料|调料|食材)$/.test(name) && !amount) continue;

      /* 判定所属分组：找最后一个在 row 之前的分组标题；没有则默认 main */
      let group = 'main';
      if (groupHeaders.length) {
        let lastG = 'main';
        for (const h of groupHeaders) {
          if (h.el.compareDocumentPosition(row) & Node.DOCUMENT_POSITION_FOLLOWING) {
            lastG = h.group;
          } else {
            break;
          }
        }
        group = lastG;
      }

      const item = { name, amount };
      ingredients.push(item);
      ingredientGroups[group].push(item);
    }
    if (!ingredients.length) warnings.push('ingredients:empty-after-parse');
  } else {
    warnings.push('ingredients:root-not-found');
  }

  /* 步骤 */
  const steps = [];
  const stepNodes = document.querySelectorAll(
    '.steps > li, .recipe-steps > li, .steps li, .recipe-step, .step-item',
  );
  let index = 0;
  for (const el of stepNodes) {
    index += 1;
    const img = el.querySelector('img');
    const textEl = el.querySelector('.text, .step-text, .desc, p');

    let text = '';
    if (textEl) {
      const clone = textEl.cloneNode(true);
      clone
        .querySelectorAll('.number, .step-index, .step-number, .step-no, script, style')
        .forEach((n) => n.remove());
      text = norm(clone.textContent);
    }
    if (!text) {
      const clone = el.cloneNode(true);
      clone
        .querySelectorAll('img, .number, .step-index, .step-number, .step-no, .step-image, script, style')
        .forEach((n) => n.remove());
      text = norm(clone.textContent).replace(/^步骤\s*\d+\s*/, '');
    }
    const image = clean(img?.getAttribute('data-src') || img?.getAttribute('src'));

    if (!text && !image) continue;
    steps.push({ index: steps.length + 1, text, image });
  }
  if (!steps.length) warnings.push('steps:not-found');

  /* 小贴士 */
  let tips = pickText('.recipe-tips', '.recipe-tip', '.tips-content', '.note');
  if (tips.length > 2000) tips = tips.slice(0, 2000);

  /* 标签 / 分类 */
  const tags = [];
  const tagSeen = new Set();
  for (const anchor of document.querySelectorAll(
    '.recipe-tags a, .normal-recipe-tags a, .recipe-category a, .tags a, .recipe-show .tags a',
  )) {
    const value = norm(anchor.textContent);
    if (!value || value.length > 20 || tagSeen.has(value)) continue;
    tagSeen.add(value);
    tags.push(value);
  }

  /* 做过 / 收藏数 */
  const statScope = pick('.recipe-show', '.recipe-main', '#main', 'body') || document.body;
  const statText = norm(statScope.innerText || statScope.textContent).slice(0, 4000);
  const madeCount = (statText.match(/([\d.]+[万千百]?)\s*(?:人)?做过/) || [])[1] || '';
  const favCount = (statText.match(/([\d.]+[万千百]?)\s*收藏/) || [])[1] || '';

  const pageUrl = String((ctx && ctx.pageUrl) || document.baseURI || '');
  const idMatch = pageUrl.match(/\/recipe\/(\d+)/);

  return {
    id: idMatch ? idMatch[1] : '',
    url: pageUrl.split('?')[0],
    title,
    description,
    coverImage,
    author,
    servings,
    ingredients,
    ingredientGroups,
    steps,
    tips,
    tags,
    madeCount,
    favCount,
    warnings,
    pageUrl,
    pageTitle: document.title,
  };
}

module.exports = {
  RECIPE_HREF_RE,
  RECIPE_URL_RE,
  parseRecipeId,
  isRecipeUrl,
  extractListInPage,
  extractRecipeInPage,
};
