import Foundation
import WebKit

/// 解析器输出的原始结构（对应 src/scraper/parse.js 里 extractRecipeInPage 的返回值）
struct RawRecipeStep: Decodable {
    var index: Int?
    var text: String?
    var image: String?
}

struct RawIngredient: Decodable {
    var name: String?
    var amount: String?
}

struct RawRecipe: Decodable {
    var id: String?
    var url: String?
    var title: String?
    var description: String?
    var coverImage: String?
    var author: String?
    var servings: String?
    var ingredients: [RawIngredient]?
    var steps: [RawRecipeStep]?
    var tips: String?
    var tags: [String]?
    var madeCount: String?
    var favCount: String?
    var pageUrl: String?
    var warnings: [String]?
}

/**
 * HTML → 数据 的解析器：直接跑 `src/scraper/parse.js`（工程里以 bundle resource 引入，
 * 与网页端共用同一份解析逻辑），执行环境是一个不可见、且**屏蔽了所有外部资源加载**的 WKWebView，
 * 这样解析时不联网，不会触发站点风控。
 */
@MainActor
final class RecipeParser {
    private let webView: WKWebView
    private let parseScript: String
    private let navigationDelegate = HTMLNavigationDelegate()

    static func create() async throws -> RecipeParser {
        guard let url = Bundle.main.url(forResource: "parse", withExtension: "js") else {
            throw ScrapeError(code: .parseFailed, message: "App 里缺少解析脚本，检查构建资源是否包含 src/scraper/parse.js")
        }
        let script = try String(contentsOf: url, encoding: .utf8)
        return RecipeParser(script: script)
    }

    private init(script: String) {
        self.parseScript = script

        let config = WKWebViewConfiguration()
        if let ruleList = Self.makeBlockRemoteRules() {
            config.userContentController.add(ruleList)
        }
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = SiteClient.userAgent
        view.navigationDelegate = navigationDelegate
        self.webView = view
    }

    /// 屏蔽一切外部资源加载（对应网页端 dom.js 里 `page.route('**/*')` 的拦截）
    private static func makeBlockRemoteRules() -> WKContentRuleList? {
        let json = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","script","style","font","fetch","xmlhttprequest","websocket","popup"]},"action":{"type":"block"}}]
        """
        let semaphore = DispatchSemaphore(value: 0)
        var list: WKContentRuleList?
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "block-remote-resources",
            encodedContentRuleList: json
        ) { ruleList, _ in
            list = ruleList
            semaphore.signal()
        }
        semaphore.wait()
        return list
    }

    func close() {
        webView.stopLoading()
    }

    /// 同 dom.js HtmlParser.run：注入 <base href>，渲染后调用 extractRecipeInPage
    func extractRecipe(html: String, pageUrl: String) async throws -> RawRecipe {
        let escaped = pageUrl.replacingOccurrences(of: "\"", with: "&quot;")
        let baseTag = "<base href=\"\(escaped)\">"
        let document: String
        if let range = html.range(of: "<head[^>]*>", options: .regularExpression) {
            document = html.replacingCharacters(in: range, with: html[range] + baseTag)
        } else {
            document = baseTag + html
        }

        guard let baseURL = URL(string: pageUrl) else {
            throw ScrapeError(code: .parseFailed, message: "菜谱地址无效")
        }

        await load(html: document, baseURL: baseURL)

        // parse.js 里有个 module.exports，用一个假的 module 对象兜住
        let script = """
        (function () {
          var module = { exports: {} };
          \(parseScript)
          return JSON.stringify(extractRecipeInPage({ pageUrl: \(Self.jsString(pageUrl)) }));
        })()
        """

        let anyValue = try await evaluate(script)
        guard let json = anyValue as? String, let data = json.data(using: .utf8) else {
            throw ScrapeError(code: .parseFailed, message: "解析脚本没有返回数据")
        }
        do {
            return try JSONDecoder().decode(RawRecipe.self, from: data)
        } catch {
            throw ScrapeError(code: .parseFailed, message: "解析结果无法识别：\(error.localizedDescription)")
        }
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private func load(html: String, baseURL: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigationDelegate.onFinish = { continuation.resume() }
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func evaluate(_ script: String) async throws -> Any {
        if let value = try? await webView.evaluateJavaScript(script) {
            return value
        }
        throw ScrapeError(code: .parseFailed, message: "解析脚本执行失败")
    }
}

private final class HTMLNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?()
    }
}
