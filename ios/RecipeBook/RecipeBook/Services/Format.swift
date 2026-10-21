import Foundation

enum ISOStamp {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }
}

enum Format {
    /// 2026-09-17 17:26
    static func dateTime(_ value: String) -> String {
        guard let date = ISOStamp.date(from: value) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func bytes(_ value: Int) -> String {
        let v = Double(value)
        if v < 1024 { return "\(value) B" }
        if v < 1024 * 1024 { return String(format: "%.1f KB", v / 1024) }
        if v < 1024 * 1024 * 1024 { return String(format: "%.1f MB", v / 1024 / 1024) }
        return String(format: "%.2f GB", v / 1024 / 1024 / 1024)
    }
}
