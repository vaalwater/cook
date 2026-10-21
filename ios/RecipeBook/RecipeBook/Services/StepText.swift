import Foundation

/// 步骤文本里的时间片段高亮，与网页端 app.js 的 highlightStepTime 同一套匹配：
/// 先找 "30 分钟" 这类数字时间，再找 "一小时"、"两刻钟" 这类中文时间。
enum StepText {
    private static let digitTime = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?\s*(?:秒|分钟|个小时|半小时|小时|hour|hours|minute|minutes|sec|secs|min|mins|hr|hrs|h|min))"#,
        options: [.caseInsensitive]
    )

    private static let cnTime = try! NSRegularExpression(
        pattern: #"((?:[一二两三四五六七八九]十[一二三四五六七八九]?|[一二三四五六七八九]十|[一二两三四五六七八九十半几]))(?:个)?(小时|分钟|刻钟|秒)"#,
        options: []
    )

    struct Segment {
        var value: String
        var isTime: Bool
    }

    static func segments(_ text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let utf16Length = text.utf16.count

        var ranges: [NSRange] = []
        for regex in [digitTime, cnTime] {
            for match in regex.matches(in: text, options: [], range: nsRange) {
                let range = match.range
                // 数字后面紧跟英文字母（ml / kg）时不算时长
                let end = NSMaxRange(range)
                if end < utf16Length {
                    let next = text[String.Index(utf16Offset: end, in: text)]
                    if (next >= "a" && next <= "z") || (next >= "A" && next <= "Z") { continue }
                }
                if !ranges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                    ranges.append(range)
                }
            }
        }

        guard !ranges.isEmpty else { return [Segment(value: text, isTime: false)] }
        let sorted = ranges.sorted { $0.location < $1.location }

        var result: [Segment] = []
        var cursor = 0
        for range in sorted {
            guard range.location >= cursor else { continue }
            let gap = NSRange(location: cursor, length: range.location - cursor)
            if gap.length > 0, let textRange = Range(gap, in: text), let value = Optional(String(text[textRange])) {
                result.append(Segment(value: value, isTime: false))
            }
            if let textRange = Range(range, in: text) {
                result.append(Segment(value: String(text[textRange]), isTime: true))
            }
            cursor = NSMaxRange(range)
        }
        if cursor < utf16Length {
            let tail = NSRange(location: cursor, length: utf16Length - cursor)
            if let textRange = Range(tail, in: text) {
                result.append(Segment(value: String(text[textRange]), isTime: false))
            }
        }
        return result
    }
}
