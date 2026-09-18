'use strict';

const fs = require('node:fs');
const { chromium } = require('playwright');
const { PATHS, ensureDirs } = require('../paths');

const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/**
 * 使用持久化用户目录启动 Chromium。
 * 登录态（cookies / localStorage）会自动保存在 data/browser-profile，
 * 下次启动无需重新登录。
 */
async function launchBrowser({ headless = false, slowMo = 0 } = {}) {
  ensureDirs();
  const context = await chromium.launchPersistentContext(PATHS.PROFILE_DIR, {
    headless,
    slowMo,
    viewport: { width: 1440, height: 960 },
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai',
    userAgent: USER_AGENT,
    ignoreDefaultArgs: ['--enable-automation'],
    args: ['--disable-blink-features=AutomationControlled', '--start-maximized'],
  });

  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  });

  return context;
}

/** 通过 cookie 判断是否已登录（下厨房的会话 cookie 含 session） */
async function hasSessionCookie(context) {
  try {
    const cookies = await context.cookies('https://www.xiachufang.com/');
    return cookies.some((c) => /session/i.test(c.name) && c.value && c.value.length > 8);
  } catch {
    return false;
  }
}

/**
 * 结合 cookie 与页面 DOM 判断登录态。
 * 返回 { loggedIn, reason }
 */
async function detectLogin(context, page) {
  if (!(await hasSessionCookie(context))) {
    return { loggedIn: false, reason: 'no-session-cookie' };
  }
  if (!page) return { loggedIn: true, reason: 'cookie' };

  const domHint = await page
    .evaluate(() => {
      const text = (document.body && document.body.innerText) || '';
      if (/退出登录|我的下厨房|我的主页/.test(text)) return 'in';
      if (/登录\s*\/\s*注册|立即登录/.test(text)) return 'out';
      return 'unknown';
    })
    .catch(() => 'unknown');

  if (domHint === 'out') return { loggedIn: false, reason: 'page-shows-login' };
  return { loggedIn: true, reason: domHint === 'in' ? 'cookie+dom' : 'cookie' };
}

/** 把当前登录状态落盘一份，便于排查 / 迁移 */
async function saveStorageState(context) {
  ensureDirs();
  try {
    await context.storageState({ path: PATHS.STATE_FILE });
    return true;
  } catch {
    return false;
  }
}

function hasSavedProfile() {
  try {
    return fs.readdirSync(PATHS.PROFILE_DIR).length > 0;
  } catch {
    return false;
  }
}

module.exports = {
  USER_AGENT,
  launchBrowser,
  hasSessionCookie,
  detectLogin,
  saveStorageState,
  hasSavedProfile,
};
