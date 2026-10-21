import Foundation

struct ScheduledStep: Hashable, Identifiable {
    let step: RecipeStep
    let start: Double
    let end: Double
    let passive: Bool

    var id: String { "\(step.index)-\(Int(start))" }
    var minutes: Double { end - start }
}

struct CookLane: Identifiable {
    let recipeId: Int
    let recipeTitle: String
    let coverImage: String
    let servings: String
    var steps: [ScheduledStep]

    var id: Int { recipeId }
    var finishAt: Double { steps.last?.end ?? 0 }
}

struct AggregatedIngredient: Identifiable, Hashable {
    let key: String
    let name: String
    let amounts: [String]
    let recipes: Int

    var id: String { key }
}

/// 多菜谱统筹调度：单厨师 + 多锅并行，事件驱动模拟。
/// 直接移植网页端 app.js 的 scheduleRecipes，保证两端排出来的时间线一致。
enum CookScheduler {
    private static let passivePattern = try! NSRegularExpression(
        pattern: #"(炖|焖|煮|蒸|烤|煲|卤|焙|烩|熬|煨|沸)"#, options: []
    )

    static func isPassiveStep(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let nsText = text as NSString
        return passivePattern.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) != nil
    }

    private final class Runner {
        let order: Int
        let recipe: Recipe
        let items: [(step: RecipeStep, duration: Double, passive: Bool)]
        var idx = 0
        var cursor: Double = 0
        var lane: CookLane

        init(order: Int, recipe: Recipe) {
            self.order = order
            self.recipe = recipe
            self.items = recipe.steps.compactMap { step -> (step: RecipeStep, duration: Double, passive: Bool)? in
                let duration = TimeEstimator.stepMinutes(step)
                guard duration > 0 else { return nil }
                let passive = CookScheduler.isPassiveStep(step.text)
                return (step: step, duration: duration, passive: passive)
            }
            self.lane = CookLane(
                recipeId: recipe.id,
                recipeTitle: recipe.displayTitle,
                coverImage: recipe.coverImage,
                servings: recipe.servings,
                steps: []
            )
        }

        /// 做完当前步骤后，紧跟着能解锁的被动时长
        func unlockPassive() -> Double {
            let next = idx + 1
            guard next < items.count, items[next].passive else { return 0 }
            return items[next].duration
        }

        /// 剩余被动总时长（长炖煮的菜优先启动）
        func remainPassive() -> Double {
            var sum: Double = 0
            var i = idx
            while i < items.count {
                if items[i].passive { sum += items[i].duration }
                i += 1
            }
            return sum
        }
    }

    static func schedule(_ recipes: [Recipe]) -> (lanes: [CookLane], globalEnd: Double) {
        let runners = recipes.enumerated().map { Runner(order: $0.offset, recipe: $0.element) }
        var workerCursor: Double = 0
        var globalEnd: Double = 0
        let totalSteps = runners.reduce(0) { $0 + $1.items.count }
        var done = 0

        while done < totalSteps {
            // 1. 被动步骤：一到就绪时刻立即开火，只占锅不占厨师
            for runner in runners {
                while runner.idx < runner.items.count, runner.items[runner.idx].passive {
                    let item = runner.items[runner.idx]
                    let end = runner.cursor + item.duration
                    runner.lane.steps.append(
                        ScheduledStep(step: item.step, start: runner.cursor, end: end, passive: true)
                    )
                    runner.cursor = end
                    runner.idx += 1
                    done += 1
                    if end > globalEnd { globalEnd = end }
                }
            }

            // 2. 主动步骤：挑一个厨师最早能做的，优先"完成后能解锁最长炖煮"的
            let candidates = runners.filter { $0.idx < $0.items.count && !$0.items[$0.idx].passive }
            if candidates.isEmpty { break }

            let earliest = candidates.map { max($0.cursor, workerCursor) }.min() ?? 0
            var ready = candidates.filter { $0.cursor <= earliest }
            ready.sort { a, b in
                if a.unlockPassive() != b.unlockPassive() { return a.unlockPassive() > b.unlockPassive() }
                if a.remainPassive() != b.remainPassive() { return a.remainPassive() > b.remainPassive() }
                return a.order < b.order
            }

            guard let runner = ready.first else { break }
            let item = runner.items[runner.idx]
            let start = max(runner.cursor, workerCursor)
            let end = start + item.duration
            runner.lane.steps.append(
                ScheduledStep(step: item.step, start: start, end: end, passive: false)
            )
            runner.cursor = end
            runner.idx += 1
            done += 1
            workerCursor = end
            if end > globalEnd { globalEnd = end }
        }

        let lanes = runners.map { $0.lane }.filter { !$0.steps.isEmpty }
        return (lanes, globalEnd)
    }

    /// 食材名归一化：去空白 / 标点，按"相同原料"聚合
    static func normalizeIngredientName(_ name: String) -> String {
        let lowered = name.lowercased().replacingOccurrences(of: "\u{3000}", with: "")
        let bad: Set<Character> = Set(" ，、。；：,.;:()（）【】[]\\/·•".map { $0 })
        let cleaned = lowered.filter { !$0.isWhitespace && !bad.contains($0) }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    static func aggregate(_ recipes: [Recipe]) -> (main: [AggregatedIngredient], seasoning: [AggregatedIngredient]) {
        var mainMap: [String: (name: String, amounts: [String], recipes: Int)] = [:]
        var seasonMap: [String: (name: String, amounts: [String], recipes: Int)] = [:]

        for recipe in recipes {
            for (target, items) in [("main", recipe.ingredientGroups.main), ("seasoning", recipe.ingredientGroups.seasoning)] {
                for item in items {
                    let key = normalizeIngredientName(item.name)
                    if key.isEmpty { continue }
                    if target == "main" {
                        if mainMap[key] == nil { mainMap[key] = (item.name, [], 0) }
                        mainMap[key]!.amounts.append(item.amount)
                        mainMap[key]!.recipes += 1
                    } else {
                        if seasonMap[key] == nil { seasonMap[key] = (item.name, [], 0) }
                        seasonMap[key]!.amounts.append(item.amount)
                        seasonMap[key]!.recipes += 1
                    }
                }
            }
        }

        let convert: ([String: (name: String, amounts: [String], recipes: Int)]) -> [AggregatedIngredient] = { map in
            map.map { key, value in
                AggregatedIngredient(key: key, name: value.name, amounts: value.amounts, recipes: value.recipes)
            }
            .sorted { a, b in
                if a.recipes != b.recipes { return a.recipes > b.recipes }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }

        return (convert(mainMap), convert(seasonMap))
    }
}
