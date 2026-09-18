'use strict';

/**
 * 半自动登录。
 *
 * 下厨房会对自动化浏览器下发滑动验证码，所以这里只在「登录」这一步使用浏览器：
 *   1. 打开可见的 Chromium 窗口；
 *   2. 你手动完成登录（扫码 / 账号密码，遇到滑块验证也一并处理）；
 *   3. 脚本检测到会话 Cookie 后自动保存到 data/cookies.json 并关闭浏览器。
 *
 * 之后抓取阶段直接用这份 Cookie 走 HTTP 请求，不再需要浏览器。
 *
 * 用法：
 *   npm run login
 *   node --no-warnings src/scraper/login.js --url <合集URL> --timeout 600
 */

const { launchBrowser, saveStorageState } = require('./browser');
const { BASE_URL, LOGIN_URL, saveCookies, filterSiteCookies, hasSessionCookie, sleep } = require('./session');

function log(message) {
  process.stdout.write(`[LOGIN] ${message}\n`);
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

async function readSiteCookies(context) {
  try {
    return filterSiteCookies(await context.cookies(BASE_URL));
  } catch {
    return [];
  }
}

/** 最终地址是否仍是人机校验页 */
function isCaptchaUrl(url) {
  return /humancheck_captcha|\/auth\/humancheck/i.test(url || '');
}

/**
 * 响应的 HTML 是否是验证页（有些风控不重定向，而是直接返回验证页内容）
 */
function looksLikeCaptcha(html) {
  if (!html) return false;
  const head = html.slice(0, 12000);
  return /humancheck|滑块验证|拖动滑块|请完成安全验证/.test(head);
}

/**
 * 在浏览器上下文里探测目标页，看是否还会被弹到滑块验证页。
 *
 * 为什么不用「有没有 session cookie」来判断：过滑块并不需要登录，
 * 站点只会下发 xcf_clearance。只认 session cookie 的话，
 * 用户拖完滑块也永远不会被判为通过，会一直干等到超时。
 */
async function probeTargetInBrowser(page, target) {
  if (!page || page.isClosed()) return { reachable: false, closed: true };
  return page
    .evaluate(async (url) => {
      try {
        // 走浏览器自身的网络栈，带上真实的 Cookie 与指纹
        const res = await fetch(url, { redirect: 'follow', credentials: 'include' });
        let html = '';
        try {
          html = await res.text();
        } catch {
          /* 拿不到正文时退化成仅按 URL 判断 */
        }
        return { reachable: true, finalUrl: res.url || '', status: res.status, html };
      } catch (error) {
        return { reachable: false, error: String((error && error.message) || error) };
      }
    }, target)
    .then((result) => ({
      ...result,
      blocked: isCaptchaUrl(result.finalUrl) || looksLikeCaptcha(result.html),
    }))
    .catch((error) => ({ reachable: false, blocked: true, error: String((error && error.message) || error) }));
}

/**
 * 打开浏览器等待人工处理，完成后保存 Cookie。
 *
 * requireLogin = true  ：必须登录成功（拿到会话 Cookie）才算完成，用于「登录下厨房」。
 * requireLogin = false ：只要目标页不再被人机校验拦截就算完成，用于抓取途中的风控恢复。
 *
 * @param {{
 *   url?:string,
 *   probeUrl?:string,
 *   requireLogin?:boolean,
 *   timeoutSec?:number,
 *   onEvent?:(event:object)=>void,
 * }} options
 */
async function runLoginFlow({
  url = LOGIN_URL,
  probeUrl = '',
  requireLogin = true,
  timeoutSec = 600,
  onEvent = () => {},
} = {}) {
  const notify = (event) => {
    try {
      onEvent(event);
    } catch {
      /* ignore */
    }
  };

  const context = await launchBrowser({ headless: false });
  try {
    const page = context.pages()[0] || (await context.newPage());
    await page.goto(url, { waitUntil: 'domcontentloaded' }).catch(() => {});
    // 窗口可能被主窗口挡住，主动提到最前面
    await page.bringToFront().catch(() => {});

    let cookies = await readSiteCookies(context);

    // 只有「登录」场景才把已有会话当作完成；
    // 「过风控」场景可能是会话还在但被滑块拦住，不能在这里提前返回
    if (requireLogin && hasSessionCookie(cookies)) {
      saveCookies(cookies);
      notify({ type: 'log', message: '检测到已有登录会话，直接复用。' });
      notify({ type: 'login-ok' });
      return { ok: true, cookies, reused: true };
    }

    notify({ type: 'login-required', timeout: timeoutSec, requireLogin });
    notify({
      type: 'log',
      message: requireLogin
        ? '已打开浏览器窗口，请在其中完成登录（遇到滑块验证请一并拖动通过）。窗口可能被主窗口挡住，注意任务栏。'
        : '已打开浏览器窗口，请拖动滑块完成人机校验。窗口可能被主窗口挡住，注意任务栏。',
    });

    const startedAt = Date.now();
    let lastBeatAt = 0;

    const finish = async (reason) => {
      // 多等一会，确保 xcf_clearance 这类附属 Cookie 已经写入
      await sleep(1800);
      const latest = await readSiteCookies(context);
      if (latest.length) cookies = latest;
      saveCookies(cookies);
      await saveStorageState(context);
      notify({ type: 'log', message: `${reason}，已保存 ${cookies.length} 条 Cookie，继续。` });
      notify({ type: 'login-ok' });
      await sleep(800);
      return { ok: true, cookies, reused: false };
    };

    while (Date.now() - startedAt < timeoutSec * 1000) {
      await sleep(2000);

      if (page.isClosed()) {
        notify({ type: 'log', message: '浏览器窗口已关闭，人工处理已中止。' });
        return { ok: false, cookies: [] };
      }

      cookies = await readSiteCookies(context);

      // 「登录」场景：出现会话 Cookie 即算完成
      if (requireLogin && hasSessionCookie(cookies)) {
        return finish('登录成功');
      }

      // 「过风控」场景：目标页不再被弹到滑块页即算完成
      if (!requireLogin && probeUrl) {
        const probe = await probeTargetInBrowser(page, probeUrl);
        if (probe.reachable && !probe.blocked) {
          return finish('已通过人机校验');
        }
      }

      const elapsed = Math.round((Date.now() - startedAt) / 1000);
      // 每 10 秒报一次，让界面看得出程序还活着
      // （原来用 elapsed % 30 === 0 判断，因为循环间隔取整几乎不可能命中）
      if (elapsed - lastBeatAt >= 10) {
        lastBeatAt = elapsed;
        const hint = requireLogin ? '仍在等待登录' : '仍在等待滑块验证通过';
        notify({ type: 'log', message: `${hint}……（已等待 ${elapsed}s）` });
      }
    }

    notify({
      type: 'log',
      message: requireLogin
        ? `等待登录超时（${timeoutSec}s），未获取到登录态。`
        : `等待人机校验超时（${timeoutSec}s）。可以稍后重试，或把请求间隔调大一些。`,
    });
    return { ok: false, cookies: [] };
  } catch (error) {
    notify({ type: 'log', message: `登录流程出错：${error.message}` });
    return { ok: false, cookies: [] };
  } finally {
    await context.close().catch(() => {});
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = await runLoginFlow({
    url: typeof args.url === 'string' ? args.url : LOGIN_URL,
    timeoutSec: Number(args.timeout || 600),
    onEvent: (event) => {
      if (event.type === 'log') log(event.message);
    },
  });

  if (result.ok) {
    log(`SUCCESS 登录态已保存到 data/cookies.json，可以开始抓取了。`);
  } else {
    log(`FAILED 未获取到有效登录态，请重试 npm run login。`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((error) => {
    log(`FAILED ${error && error.message ? error.message : error}`);
    process.exitCode = 1;
  });
}

module.exports = { runLoginFlow };
