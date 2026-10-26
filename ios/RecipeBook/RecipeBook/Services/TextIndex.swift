import Foundation

/// 检索索引规则（纯子串匹配，多词之间是 AND）：
/// 索引归一化（小写 + 去空白 + 去标点），查询按标点/空格切词，多词之间是 AND。
enum TextIndex {
    private static let punctuation: Set<Character> = Set(
        ",，、。;；:：|/\\_+()（）[]【】{}<>\"'“”‘’~!！?？@#$%^&*=".map { $0 }
    )

    static func normalize(_ value: String?) -> String {
        let lowered = (value ?? "").lowercased().replacingOccurrences(of: "\u{00A0}", with: "")
        let noSpace = lowered.filter { !$0.isWhitespace }
        return String(noSpace.filter { !punctuation.contains($0) })
    }

    static func tokens(_ value: String?) -> [String] {
        var text = (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        text = text.replacingOccurrences(of: "-", with: " ")
        text = text.replacingOccurrences(of: "–", with: " ")
        text = text.replacingOccurrences(of: "—", with: " ")
        text = String(text.map { punctuation.contains($0) ? " " : $0 })
        return text.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init).filter { !$0.isEmpty }
    }

    static func buildIndex(for recipe: Recipe) -> String {
        // 作者名不进索引：不是菜谱内容，还会把「作者叫小土豆」的南瓜饼搜出来
        var parts: [String] = [
            recipe.title,
            recipe.description,
            recipe.servings,
            recipe.tips,
        ]
        for item in recipe.ingredients {
            parts.append(item.name)
            parts.append(item.amount)
        }
        for step in recipe.steps {
            parts.append(step.text)
        }
        parts.append(contentsOf: recipe.tags)
        return normalize(parts.joined(separator: " "))
    }

    static func matches(_ recipe: Recipe, tokens: [String]) -> Bool {
        if tokens.isEmpty { return true }
        let index = recipe.searchIndex
        for token in tokens {
            if !index.contains(normalize(token)) { return false }
        }
        return true
    }
}
