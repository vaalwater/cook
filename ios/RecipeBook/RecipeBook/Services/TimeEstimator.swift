import Foundation

/// 步骤用时估算：文本里有显式时间就解析，没有再按动词查表估算。
/// 优先解析文本里显式写出的时间（"小火炖 30 分钟"、"一小时"…），
/// 没有时间描述时按动词关键词估算（烤 25 分钟、焖 30 分钟…）。
enum TimeEstimator {
    // MARK: - 显式时间解析

    private static let hourRe = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(?:小时|个小时|hour|hours|hr|hrs|h)"#,
        options: [.caseInsensitive]
    )
    private static let minuteRe = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(?:分钟|minute|minutes|min|mins|m)"#,
        options: [.caseInsensitive]
    )
    private static let secondRe = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(?:秒|sec|secs|second|seconds)"#,
        options: [.caseInsensitive]
    )
    private static let cnTimeRe = try! NSRegularExpression(
        pattern: #"((?:[一二两三四五六七八九]十[一二三四五六七八九]?|[一二三四五六七八九]十|[一二两三四五六七八九十半几]))(?:个)?(小时|分钟|刻钟|秒)"#,
        options: []
    )
    private static let cnTimeTest = try! NSRegularExpression(
        pattern: #"[一二两三四五六七八九十半几](?:个)?(?:小时|分钟|刻钟|秒)"#,
        options: []
    )

    private static let cnNumbers: [Character: Double] = [
        "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7,
        "八": 8, "九": 9, "十": 10, "半": 0.5, "几": 2,
    ]
    private static let cnUnitMinutes: [String: Double] = [
        "小时": 60, "分钟": 1, "刻钟": 15, "秒": 1.0 / 60.0,
    ]

    static func hasExplicitTime(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if hourRe.firstMatch(in: text, options: [], range: range) != nil { return true }
        if minuteRe.firstMatch(in: text, options: [], range: range) != nil { return true }
        if secondRe.firstMatch(in: text, options: [], range: range) != nil { return true }
        return cnTimeTest.firstMatch(in: text, options: [], range: range) != nil
    }

    /// 数字 + 单位后面紧跟英文字母（ml / kg …）时不算时长
    private static func isBoundary(_ text: String, _ result: NSTextCheckingResult) -> Bool {
        let endIndex = text.index(text.startIndex, offsetBy: NSMaxRange(result.range), limitedBy: text.endIndex)
        guard let idx = endIndex, idx < text.endIndex else { return true }
        let next = text[idx]
        return !(next >= "a" && next <= "z") && !(next >= "A" && next <= "Z")
    }

    private static func number(in text: String, from result: NSTextCheckingResult) -> Double? {
        guard result.numberOfRanges > 1, let r = Range(result.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    private static func cnValue(_ s: String) -> Double {
        let chars = Array(s)
        if chars.count == 1, let v = cnNumbers[chars[0]] { return v }
        if chars.count == 2, chars[1] == "十" { return (cnNumbers[chars[0]] ?? 0) * 10 }
        if chars.count == 3, chars[1] == "十" {
            return (cnNumbers[chars[0]] ?? 0) * 10 + (cnNumbers[chars[2]] ?? 0)
        }
        return 0
    }

    static func parseTimeToMinutes(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var minutes: Double = 0
        var matched = false

        for (regex, factor) in [(hourRe, 60.0), (minuteRe, 1.0), (secondRe, 1.0 / 60.0)] {
            for result in regex.matches(in: text, options: [], range: range) {
                guard isBoundary(text, result), let value = number(in: text, from: result) else { continue }
                minutes += value * factor
                matched = true
            }
        }

        for result in cnTimeRe.matches(in: text, options: [], range: range) {
            guard result.numberOfRanges > 2,
                  let nRange = Range(result.range(at: 1), in: text),
                  let uRange = Range(result.range(at: 2), in: text) else { continue }
            let n = cnValue(String(text[nRange]))
            let unit = String(text[uRange])
            if n > 0, let factor = cnUnitMinutes[unit] {
                minutes += n * factor
                matched = true
            }
        }

        return matched ? minutes : 0
    }

    // MARK: - 动词估算

    private static let rules: [(NSRegularExpression, Double)] = [
        (#"(烤箱|烘烤|烤制|烤至|烤好|烤出|烤到)"#, 25),
        (#"(慢炖|炖煮|小火炖|小火煲)"#, 45),
        (#"(焖煮|焖制|焖)"#, 30),
        (#"(大火煮|中火煮|小火煮|水煮|汆|氽|白灼)"#, 10),
        (#"(蒸制|蒸熟|蒸至|上锅蒸|隔水蒸)"#, 18),
        (#"(油炸|复炸|炸至|炸到|煎炸)"#, 6),
        (#"(煎制|煎至|煎到|煎)"#, 5),
        (#"(煸炒|翻炒|爆炒|大火爆炒|清炒)"#, 3),
        (#"(腌制|腌渍|泡发|浸泡)"#, 30),
        (#"(醒发|发酵|饧发|发面)"#, 60),
        (#"(冷藏|冷冻|冰镇)"#, 30),
        (#"(切丝|切片|切块|切碎|切丁|剁|拍碎|拍扁)"#, 2),
        (#"(搅拌|拌匀|混合|搅匀|揉)"#, 2),
        (#"(热锅|起锅|烧热|预热)"#, 2),
        (#"(撒上|摆盘|装盘|出锅|盛出|淋上)"#, 1),
        (#"(煮|烧|烫)"#, 8),
        (#"(削皮|削)"#, 5),
        (#"切"#, 2),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }

    static func estimateStepMinutes(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        for (regex, minutes) in rules {
            if regex.firstMatch(in: text, options: [], range: range) != nil { return minutes }
        }
        return 1
    }

    static func stepMinutes(_ step: RecipeStep) -> Double {
        let text = step.text
        if hasExplicitTime(text) { return parseTimeToMinutes(text) }
        return estimateStepMinutes(text)
    }

    // MARK: - 展示

    static func format(_ minutes: Double) -> String {
        let total = Int(round(minutes))
        if total < 60 { return "\(total) 分钟" }
        let h = total / 60
        let m = total - h * 60
        return m > 0 ? "\(h) 小时 \(m) 分钟" : "\(h) 小时"
    }

    /// 时间轴刻度的紧凑格式：0 / 30′ / 1h30 / 2h
    static func axisCompact(_ minutes: Double) -> String {
        let t = Int(round(minutes))
        if t == 0 { return "0" }
        let h = t / 60
        let m = t - h * 60
        if h == 0 { return "\(m)′" }
        return m > 0 ? "\(h)h\(m)" : "\(h)h"
    }

    /// 在 [0, total] 上挑 4~6 个等距刻度（端点必含）
    static func axisTicks(total: Double) -> [Double] {
        guard total > 0 else { return [] }
        var targets: [Double] = [0, total]
        let niceSteps: [Double] = [1, 2, 5, 10, 15, 20, 30, 60, 90, 120, 180]
        var step = total / 5
        step = niceSteps.first { $0 >= step } ?? step
        if step <= 0 { step = total }
        var t = step
        while t < total {
            targets.append(t)
            t += step
        }
        let unique = NSOrderedSet(array: targets.map { min(total, round($0)) })
        return unique.array.compactMap { $0 as? NSNumber }.map { $0.doubleValue }.sorted()
    }
}
