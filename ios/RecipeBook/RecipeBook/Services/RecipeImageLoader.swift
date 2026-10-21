import UIKit

/// 图片读取：优先读 App 内置种子目录（Seed/images/...），
/// 少数远程地址（下厨房图床有防盗链）带上 Referer 现取。
final class RecipeImageLoader: @unchecked Sendable {
    static let shared = RecipeImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 沙盒里的图片目录（抓新菜谱时下载下来的图），由 RecipeStore 启动时注入；
    /// 找不到就回退到 App 内置种子目录 Seed/images
    private(set) var sandboxImageRoot: URL?

    init() {
        cache.countLimit = 300
    }

    func setSandboxImageRoot(_ url: URL) {
        sandboxImageRoot = url
    }

    func cached(_ path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func load(_ path: String) async -> UIImage? {
        if path.isEmpty { return nil }
        if let image = cached(path) { return image }

        let task: Task<UIImage?, Never> = lock.withLock {
            if let existing = tasks[path] { return existing }
            let created = Task.detached(priority: .utility) { [loader = self] in await loader.fetch(path) }
            tasks[path] = created
            return created
        }

        let image = await task.value
        if let image {
            cache.setObject(image, forKey: path as NSString)
        }
        lock.withLock { tasks[path] = nil }
        return image
    }

    private func fetch(_ path: String) async -> UIImage? {
        if path.hasPrefix("/images/") {
            let rel = String(path.dropFirst("/images/".count))
            if let root = sandboxImageRoot {
                let local = root.appendingPathComponent(rel)
                if let image = UIImage(contentsOfFile: local.path) { return image }
            }
            let seeded = Bundle.main.bundleURL
                .appendingPathComponent("Seed")
                .appendingPathComponent("images")
                .appendingPathComponent(rel)
            return UIImage(contentsOfFile: seeded.path)
        }

        guard let url = URL(string: path), let scheme = url.scheme, scheme == "http" || scheme == "https" else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("https://www.xiachufang.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }
}
