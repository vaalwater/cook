import Foundation

/**
 * 下厨房登录态（Cookie）持久化。
 *
 * Cookie 的持久化与过滤规则：
 *   - 只保留 xiachufang.com 域名下的 cookie
 *   - wait_xcf_clearance 是「待人机校验」标记，必须忽略，否则会一直被重定向到滑块验证页
 *   - session / _T_SESSION / login 里有值才算登录成功
 */
struct SiteCookie: Codable, Hashable {
    var name: String
    var value: String
    var domain: String
}

enum SessionStore {
    static let baseURL = "https://www.xiachufang.com"
    static let loginURL = "\(baseURL)/account/login/"
    static let recipeURLTemplate = "\(baseURL)/recipe/%@/"

    /// 站点下发的「待人机校验」标记，回传会导致每次请求都被重定向到滑块页
    static let ignoredCookieNames: Set<String> = ["wait_xcf_clearance"]

    static func isIgnored(_ cookie: SiteCookie) -> Bool {
        ignoredCookieNames.contains(cookie.name)
    }

    static func filterSiteCookies(_ cookies: [SiteCookie]) -> [SiteCookie] {
        cookies.filter { !isIgnored($0) && $0.domain.localizedCaseInsensitiveContains("xiachufang.com") }
    }

    static func hasSessionCookie(_ cookies: [SiteCookie]) -> Bool {
        cookies.contains { cookie in
            let name = cookie.name.lowercased()
            let looksLikeSession = name.contains("session") || name.contains("login")
            return looksLikeSession && !cookie.value.isEmpty
        }
    }

    static func cookieHeader(_ cookies: [SiteCookie]) -> String? {
        let pairs = filterSiteCookies(cookies).map { "\($0.name)=\($0.value)" }
        guard !pairs.isEmpty else { return nil }
        return pairs.joined(separator: "; ")
    }

    // MARK: - 文件读写

    private static var fileURL: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("RecipeBook/cookies.json")
    }

    struct SavedSession: Codable {
        var savedAt: String
        var cookies: [SiteCookie]
    }

    static func load() -> SavedSession? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        guard let saved = try? JSONDecoder().decode(SavedSession.self, from: data),
              !saved.cookies.isEmpty else { return nil }
        return saved
    }

    static func save(_ cookies: [SiteCookie]) {
        guard let url = fileURL else { return }
        let saved = SavedSession(savedAt: ISOStamp.string(from: Date()), cookies: cookies)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
