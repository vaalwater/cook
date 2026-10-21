import UIKit

/**
 * 图片本地化：（沿用旧实现 images.js 的规则）。
 * 下厨房图床有防盗链（必须带 Referer），图片地址形如 `<hash>_3000w_4000h.jpg`，
 * size > 0 时向图床要更小的一档，避免把 3000px 原图存到手机里。
 */
enum ImageDownloader {
    static let referer = "https://www.xiachufang.com/"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "Referer": referer,
            "User-Agent": SiteClient.userAgent,
            "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
        ]
        return URLSession(configuration: config)
    }()

    /// `<hash>_3000w_4000h.jpg` → `<hash>_1000w_1333h.jpg`
    static func resizedURL(_ url: String, size: Int) -> String {
        guard size > 0 else { return url }
        let pattern = #"^(.*)_(\d+)w_(\d+)h(\.[a-z0-9]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              match.numberOfRanges == 5 else { return url }

        func group(_ index: Int) -> String {
            Range(match.range(at: index), in: url).map { String(url[$0]) } ?? ""
        }

        guard let width = Int(group(2)), let height = Double(group(3)), width > size else { return url }
        let newHeight = Int(round((height * Double(size)) / Double(width)))
        return "\(group(1))_\(size)w_\(newHeight)h\(group(4))"
    }

    private static func fileExtension(for url: String, contentType: String?) -> String {
        if let type = contentType?.lowercased() {
            if type.contains("png") { return "png" }
            if type.contains("webp") { return "webp" }
            if type.contains("gif") { return "gif" }
            if type.contains("avif") { return "avif" }
            if type.contains("jpeg") || type.contains("jpg") { return "jpg" }
        }
        let pattern = #"\.([a-z0-9]{2,5})(?:$|[?#])"#
        if let range = url.range(of: pattern, options: .regularExpression) {
            return String(url[range]).replacingOccurrences(of: ".", with: "")
        }
        return "jpg"
    }

    struct DownloadResult {
        var ok: Bool
        var publicPath: String
        var error: String?
        var skipped: Bool
    }

    /// 下载并写入沙盒：imageDir/子目录/name.ext，返回形如 `/images/covers/123.jpg` 的公开路径
    static func download(
        _ source: String,
        to imageDir: URL,
        dirName: String,
        name: String,
        size: Int = 1000
    ) async -> DownloadResult {
        if !source.hasPrefix("http") {
            return DownloadResult(ok: true, publicPath: source, error: nil, skipped: true)
        }

        let candidates = size > 0 ? [resizedURL(source, size: size), source] : [source]
        var lastError: String?

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if data.count < 64 { throw URLError(.cannotDecodeContentData) }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }

                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
                let ext = fileExtension(for: candidate, contentType: contentType)

                let folder = imageDir.appendingPathComponent(dirName, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent("\(name).\(ext)")

                var fileData = data
                if size > 0, let image = UIImage(data: data),
                   max(image.size.width, image.size.height) > CGFloat(size),
                   let scaled = downscale(image, maxEdge: CGFloat(size)) {
                    fileData = scaled
                }
                try fileData.write(to: target)
                return DownloadResult(ok: true, publicPath: "/images/\(dirName)/\(name).\(ext)", error: nil, skipped: false)
            } catch {
                lastError = error.localizedDescription
            }
        }

        return DownloadResult(ok: false, publicPath: source, error: lastError ?? "未知错误", skipped: false)
    }

    private static func downscale(_ image: UIImage, maxEdge: CGFloat) -> Data? {
        let ratio = min(1, maxEdge / max(image.size.width, image.size.height))
        guard ratio < 1 else { return image.jpegData(compressionQuality: 0.9) }
        let size = CGSize(width: round(image.size.width * ratio), height: round(image.size.height * ratio))
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.88)
    }
}
