import Foundation

/**
 * 站内 HTTP 客户端：手动接管重定向 + Cookie Jar + 风控识别。
 *
 * 要点：
 *   - 手动接管重定向：站点会在每一跳下发风控 Cookie，必须原样带回去
 *   - 请求间隔限速 + 抖动
 *   - 识别登录跳转 / 滑块验证 / 伪装成 404 的风控
 */
enum ScrapeCode: String, Error {
    case loginRequired
    case challenge
    case notFound
    case httpError
    case network
    case parseFailed
}

struct ScrapeError: Error, LocalizedError {
    let code: ScrapeCode
    let message: String

    var errorDescription: String? { message }
}

struct FetchResult {
    let html: String
    let finalUrl: String
    let status: Int
}

final class SiteClient: @unchecked Sendable {
    /// 桌面 UA：站点对自动化浏览器会下发滑块验证码
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    var delayMs: Int = 1200

    private let session: URLSession
    private let storage: HTTPCookieStorage
    private let blocker = RedirectBlocker()
    private var lastRequestAt = Date.distantPast

    private var jar: [String: SiteCookie] = [:]

    init(cookies: [SiteCookie] = []) {
        // 让系统帮我们做 Set-Cookie 的解析（多个 Set-Cookie 头的处理比手撕字符串可靠）
        let storage = HTTPCookieStorage()
        self.storage = storage
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = storage
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        ]
        self.session = URLSession(configuration: config, delegate: blocker, delegateQueue: nil)
        setCookies(cookies)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Cookie Jar

    func setCookies(_ cookies: [SiteCookie]) {
        for cookie in SessionStore.filterSiteCookies(cookies) {
            jar[cookie.name] = cookie
            if let http = cookie.httpCookie { storage.setCookie(http) }
        }
    }

    func exportCookies() -> [SiteCookie] {
        syncJarFromStorage()
        return Array(jar.values)
    }

    var loggedIn: Bool {
        SessionStore.hasSessionCookie(Array(jar.values))
    }

    private func syncJarFromStorage() {
        guard let cookies = storage.cookies else { return }
        for cookie in cookies where cookie.domain.localizedCaseInsensitiveContains("xiachufang.com") {
            guard !SessionStore.ignoredCookieNames.contains(cookie.name) else { continue }
            jar[cookie.name] = SiteCookie(name: cookie.name, value: cookie.value, domain: cookie.domain)
        }
    }

    // MARK: - 请求

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequestAt) * 1000
        let wait = Double(delayMs) - elapsed
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000) + UInt64.random(in: 0...400_000_000))
        }
        lastRequestAt = Date()
    }

    private func request(_ url: URL, maxRedirects: Int = 6) async throws -> (HTTPURLResponse, String, URL) {
        var current = url
        var response: HTTPURLResponse?

        for _ in 0...maxRedirects {
            await throttle()
            var request = URLRequest(url: current)
            request.httpMethod = "GET"
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue(SessionStore.baseURL + "/", forHTTPHeaderField: "Referer")
            request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
            if let cookie = SessionStore.cookieHeader(Array(jar.values)) {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            let (data, urlResponse): (Data, URLResponse)
            do {
                (data, urlResponse) = try await session.data(for: request)
            } catch {
                throw ScrapeError(code: .network, message: "网络请求失败：\(error.localizedDescription)")
            }

            syncJarFromStorage()
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw ScrapeError(code: .httpError, message: "无效的响应")
            }
            response = httpResponse

            if httpResponse.statusCode >= 300, httpResponse.statusCode < 400,
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current) {
                current = next.absoluteURL
                continue
            }

            return (httpResponse, String(data: data, encoding: .utf8) ?? "", current)
        }

        guard let final = response else {
            throw ScrapeError(code: .httpError, message: "重定向次数过多")
        }
        return (final, "", current)
    }

    func fetchHtml(_ urlString: String, retries: Int = 2) async throws -> FetchResult {
        var lastError: Error?
        for attempt in 0...retries {
            do {
                let (response, html, finalURL) = try await request(URL(string: urlString)!)
                let finalUrl = finalURL.absoluteString

                if let challenge = Self.detectChallenge(html: html, finalUrl: finalUrl) {
                    throw challenge
                }
                if response.statusCode == 404 {
                    throw ScrapeError(code: .notFound, message: "页面不存在（404，也可能是风控伪装）")
                }
                if !(200..<300).contains(response.statusCode) {
                    throw ScrapeError(code: .httpError, message: "HTTP \(response.statusCode)")
                }
                return FetchResult(html: html, finalUrl: finalUrl, status: response.statusCode)
            } catch {
                lastError = error
                guard let scrape = error as? ScrapeError else { continue }
                let fatal = scrape.code == .loginRequired || scrape.code == .challenge || scrape.code == .notFound
                if fatal || attempt == retries { break }
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? ScrapeError(code: .network, message: "请求失败")
    }

    /// 探测页面是否可访问（判断登录态是否有效，单次不重试）
    func probe(_ urlString: String) async -> Result<FetchResult, ScrapeError> {
        do {
            let result = try await fetchHtml(urlString, retries: 0)
            return .success(result)
        } catch let error as ScrapeError {
            return .failure(error)
        } catch {
            return .failure(ScrapeError(code: .network, message: error.localizedDescription))
        }
    }

    // MARK: - 风控识别

    static func detectChallenge(html: String, finalUrl: String) -> ScrapeError? {
        if finalUrl.range(of: "/auth/humancheck", options: .regularExpression) != nil {
            return ScrapeError(code: .challenge, message: "触发了滑动验证，需要人工处理")
        }
        if finalUrl.range(of: "/account/(login|signup)", options: .regularExpression) != nil {
            return ScrapeError(code: .loginRequired, message: "需要登录后才能访问")
        }
        let head = String(html.prefix(4000))
        if head.range(of: "<title>\\s*滑动验证", options: .regularExpression) != nil
            || head.contains("humancheck_captcha") {
            return ScrapeError(code: .challenge, message: "触发了滑动验证，需要人工处理")
        }
        return nil
    }
}

/// 拦掉自动重定向，由 SiteClient 手动接管（每一跳都要吸收 Set-Cookie）
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension SiteCookie {
    var httpCookie: HTTPCookie? {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain.hasPrefix(".") ? domain : domain,
            .path: "/",
        ])
    }
}
