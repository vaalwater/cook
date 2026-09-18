'use strict';

/**
 * 会话与 HTTP 抓取客户端。
 *
 * 下厨房对「自动化浏览器」会下发滑动验证码，但对普通 HTTP 请求（带正常 Cookie / UA）
 * 返回的是完整服务端渲染的 HTML。因此抓取阶段走纯 HTTP，
 * 浏览器只在手动登录 / 处理风控验证时使用，然后把 Cookie 交给这里复用。
 *
 * 这里实现了一个简易 Cookie Jar，并把重定向手动接管，
 * 因为站点会在每一跳下发风控 Cookie，必须原样带回去，否则会触发验证码。
 */

const fs = require('node:fs');
const { PATHS, ensureDirs } = require('../paths');
const { USER_AGENT } = require('./browser');

const BASE_URL = 'https://www.xiachufang.com';
const LOGIN_URL = `${BASE_URL}/account/login/`;

/** 业务错误码 */
const CODES = {
  LOGIN_REQUIRED: 'LOGIN_REQUIRED',
  CHALLENGE: 'CHALLENGE',
  NOT_FOUND: 'NOT_FOUND',
  HTTP_ERROR: 'HTTP_ERROR',
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function codedError(code, message, extra = {}) {
  const error = new Error(message);
  error.code = code;
  Object.assign(error, extra);
  return error;
}

/* ------------------------------------------------------------------ */
/* Cookie 持久化                                                        */
/* ------------------------------------------------------------------ */

function loadCookies() {
  try {
    const raw = JSON.parse(fs.readFileSync(PATHS.COOKIE_FILE, 'utf8'));
    if (Array.isArray(raw.cookies) && raw.cookies.length) return raw;
  } catch {
    /* 文件不存在或损坏 */
  }
  return null;
}

function saveCookies(cookies) {
  ensureDirs();
  fs.writeFileSync(
    PATHS.COOKIE_FILE,
    JSON.stringify({ savedAt: new Date().toISOString(), cookies }, null, 2),
    'utf8',
  );
}

function cookiesToHeader(cookies) {
  return (cookies || [])
    .filter((cookie) => cookie && cookie.name)
    .map((cookie) => `${cookie.name}=${cookie.value}`)
    .join('; ');
}

function hasSessionCookie(cookies) {
  return (cookies || []).some((cookie) => /session|_T_SESSION|login/i.test(cookie.name) && cookie.value);
}

/**
 * 站点下发的「待人机校验」标记。
 * 它本身不提供任何权限，但一旦被我们回传、且会话里没有 xcf_clearance，
 * 站点就会把所有请求都重定向到滑块验证页，所以这里统一忽略它。
 */
const IGNORED_COOKIE_NAMES = new Set(['wait_xcf_clearance']);

function isIgnoredCookie(cookie) {
  return !cookie || !cookie.name || IGNORED_COOKIE_NAMES.has(cookie.name);
}

/** 只保留下厨房域名下、且不是风控标记的 cookie */
function filterSiteCookies(cookies) {
  return (cookies || []).filter(
    (cookie) =>
      !isIgnoredCookie(cookie) && /(^|\.)xiachufang\.com$/i.test(cookie.domain || ''),
  );
}

/** 是否已经拿到人机校验通过凭证 */
function hasClearance(cookies) {
  return (cookies || []).some(
    (cookie) => cookie && cookie.name === 'xcf_clearance' && Boolean(cookie.value),
  );
}

/* ------------------------------------------------------------------ */
/* HTTP 客户端                                                         */
/* ------------------------------------------------------------------ */

class SiteClient {
  constructor({ cookies = [], delayMs = 1200 } = {}) {
    this.delayMs = delayMs;
    this.lastRequestAt = 0;
    /** @type {Map<string, {name:string,value:string,domain:string}>} */
    this.jar = new Map();
    this.setCookies(cookies);
  }

  setCookies(cookies) {
    this.cookies = filterSiteCookies(cookies);
    for (const cookie of this.cookies) {
      if (cookie && cookie.name) this.jar.set(cookie.name, cookie);
    }
  }

  get loggedIn() {
    return hasSessionCookie([...this.jar.values()]);
  }

  /** 导出当前会话的全部 cookie（登录后落盘用） */
  exportCookies() {
    return [...this.jar.values()];
  }

  absorbSetCookie(response) {
    const raw =
      typeof response.headers.getSetCookie === 'function' ? response.headers.getSetCookie() : [];
    for (const line of raw) {
      const [pair, ...attrs] = String(line).split(';');
      const index = pair.indexOf('=');
      if (index <= 0) continue;
      const name = pair.slice(0, index).trim();
      const value = pair.slice(index + 1).trim();

      const domainAttr = attrs.find((attr) => /^\s*domain=/i.test(attr));
      const domain = domainAttr ? domainAttr.split('=')[1].trim() : 'www.xiachufang.com';
      if (!/xiachufang\.com$/i.test(domain)) continue;
      if (isIgnoredCookie({ name })) continue;

      const expired = /^\s*max-age=0\s*$/i.test(attrs.join(';')) || value === '';
      if (expired) {
        this.jar.delete(name);
        continue;
      }
      this.jar.set(name, { name, value, domain });
    }
  }

  async throttle() {
    const elapsed = Date.now() - this.lastRequestAt;
    const wait = this.delayMs - elapsed;
    if (wait > 0) await sleep(wait + Math.round(Math.random() * 400));
    this.lastRequestAt = Date.now();
  }

  buildHeaders(extra = {}) {
    const cookieHeader = cookiesToHeader(
      [...this.jar.values()].filter((cookie) => !isIgnoredCookie(cookie)),
    );
    return {
      'User-Agent': USER_AGENT,
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      Referer: `${BASE_URL}/`,
      'Upgrade-Insecure-Requests': '1',
      ...(cookieHeader ? { Cookie: cookieHeader } : {}),
      ...extra,
    };
  }

  /** 手动接管重定向，以便吸收每一跳下发的 Set-Cookie */
  async request(url, { maxRedirects = 6 } = {}) {
    let current = url;
    let response = null;

    for (let hop = 0; hop <= maxRedirects; hop += 1) {
      response = await fetch(current, {
        headers: this.buildHeaders(),
        redirect: 'manual',
        signal: AbortSignal.timeout(30000),
      });
      this.absorbSetCookie(response);

      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('location');
        await response.text().catch(() => '');
        if (!location) break;
        current = new URL(location, current).href;
        continue;
      }
      break;
    }

    return { response, finalUrl: current };
  }

  /**
   * 拉取页面 HTML，自动跟随重定向并识别登录 / 验证码拦截。
   * @returns {Promise<{html:string, finalUrl:string, status:number}>}
   */
  async fetchHtml(url, { retries = 2, retryDelay = 1500 } = {}) {
    let lastError = null;

    for (let attempt = 0; attempt <= retries; attempt += 1) {
      await this.throttle();
      try {
        const { response, finalUrl } = await this.request(url);
        const html = await response.text();

        const challenge = detectChallenge(html, finalUrl);
        if (challenge) throw challenge;

        if (response.status === 404) throw codedError(CODES.NOT_FOUND, '页面不存在 (404)', { url: finalUrl });
        if (!response.ok) {
          throw codedError(CODES.HTTP_ERROR, `HTTP ${response.status}`, { url: finalUrl });
        }

        return { html, finalUrl, status: response.status };
      } catch (error) {
        lastError = error;
        const fatal =
          error.code === CODES.LOGIN_REQUIRED ||
          error.code === CODES.CHALLENGE ||
          error.code === CODES.NOT_FOUND;
        if (fatal || attempt === retries) break;
        await sleep(retryDelay * (attempt + 1));
      }
    }

    throw lastError || new Error('请求失败');
  }

  /** 探测页面是否可正常访问（用于判断登录态是否有效） */
  async probe(url) {
    try {
      const result = await this.fetchHtml(url, { retries: 0 });
      return { ok: true, ...result };
    } catch (error) {
      return {
        ok: false,
        code: error.code || CODES.HTTP_ERROR,
        message: error.message,
        url: error.url || url,
      };
    }
  }
}

/** 识别登录跳转 / 滑块验证 */
function detectChallenge(html, finalUrl) {
  if (/\/auth\/humancheck/i.test(finalUrl)) {
    return codedError(CODES.CHALLENGE, '触发了滑动验证，需要人工处理', { url: finalUrl });
  }
  if (/\/account\/(login|signup)/i.test(finalUrl)) {
    return codedError(CODES.LOGIN_REQUIRED, '需要登录后才能访问', { url: finalUrl });
  }
  const head = html.slice(0, 4000);
  if (/<title>\s*滑动验证/.test(head) || /humancheck_captcha/.test(head)) {
    return codedError(CODES.CHALLENGE, '触发了滑动验证，需要人工处理', { url: finalUrl });
  }
  return null;
}

module.exports = {
  BASE_URL,
  LOGIN_URL,
  CODES,
  SiteClient,
  loadCookies,
  saveCookies,
  cookiesToHeader,
  hasSessionCookie,
  hasClearance,
  filterSiteCookies,
  isIgnoredCookie,
  detectChallenge,
  sleep,
  codedError,
};
