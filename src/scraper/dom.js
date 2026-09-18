'use strict';

/**
 * HTML → 数据 的解析器。
 *
 * 用无头 Chromium 的 DOM 能力来解析抓下来的 HTML 字符串（page.setContent），
 * 好处是解析逻辑和浏览器里完全一致，能容忍下厨房各种不规范的 HTML；
 * 这里不会访问外网，所以不会触发站点的反爬验证。
 */

const { launchBrowser } = require('./browser');

class HtmlParser {
  static async create({ headless = true } = {}) {
    const context = await launchBrowser({ headless });
    const page = context.pages()[0] || (await context.newPage());

    // 屏蔽一切外部资源，避免解析时联网、也避免误触发站点风控
    await page.route('**/*', (route) => {
      const url = route.request().url();
      if (/^https?:/i.test(url)) {
        route.abort().catch(() => {});
      } else {
        route.continue().catch(() => {});
      }
    });

    await page.setContent('<!doctype html><html><head></head><body></body></html>');
    return new HtmlParser(context, page);
  }

  constructor(context, page) {
    this.context = context;
    this.page = page;
  }

  /**
   * @param {string} html    页面 HTML
   * @param {string} pageUrl 页面真实地址（用于解析相对链接 / 推断 id）
   * @param {Function} fn    在页面上下文里执行的解析函数
   * @param {*} arg          传给解析函数的参数
   */
  async run(html, pageUrl, fn, arg) {
    const baseTag = `<base href="${String(pageUrl).replace(/"/g, '&quot;')}">`;
    const document = /<head[^>]*>/i.test(html)
      ? html.replace(/<head[^>]*>/i, (match) => match + baseTag)
      : baseTag + html;

    await this.page.setContent(document, { waitUntil: 'domcontentloaded', timeout: 30000 });
    return this.page.evaluate(fn, arg);
  }

  async close() {
    await this.context.close().catch(() => {});
  }
}

module.exports = { HtmlParser };
