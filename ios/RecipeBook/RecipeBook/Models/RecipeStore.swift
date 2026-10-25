import Foundation
import SwiftUI

enum SortKey: String, CaseIterable, Identifiable {
    case updated
    case collected
    case title
    case ingredients
    case steps
    case id
    case random

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updated: return "更新时间"
        case .collected: return "抓取时间"
        case .title: return "菜名"
        case .ingredients: return "用料数量"
        case .steps: return "步骤数量"
        case .id: return "菜谱 ID"
        case .random: return "随机"
        }
    }
}

struct PlanItem: Codable, Hashable, Identifiable {
    var id: Int
    var title: String
    var coverImage: String
    var servings: String
    var addedAt: String
}

struct RecipeQuery {
    var q: String = ""
    var tag: String = ""
    var sort: SortKey = .updated
    var ascending: Bool = false
    var page: Int = 1
    var pageSize: Int = 24

    var tokens: [String] { TextIndex.tokens(q) }
}

/// 备份文件格式：App 里抓的菜谱、删掉的菜谱、待做清单都在手机沙盒里，
/// 导出一份 JSON 就能换机 / 重装时恢复。恢复时按 updatedAt 取新者，删除记录直接生效。
struct RecipeBackup: Codable {
    var exportedAt: String
    var recipes: [Recipe]
    var plan: [PlanItem]
    var deleted: [Int]
    var updatedAt: [Int: String]
}

struct RecipeQueryResult {
    let items: [Recipe]
    let total: Int
    let page: Int
    let pageSize: Int
    var pageCount: Int { max(1, Int(ceil(Double(total) / Double(max(1, pageSize))))) }
}

/// 菜谱库：全部落在手机沙盒里。
/// Application Support/RecipeBook/
///   recipes.json   权威菜谱数据（首次启动从 App 内置种子拷贝，之后可增改删）
///   images/        抓取下载下来的封面图 / 步骤图
///   state.json     删除记录、更新时间覆盖值、待做清单
final class RecipeStore: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published var plan: [PlanItem] = []
    /// 开干模式里已完成的步骤：key = "\(recipeId)-\(stepIndex)"，随 state.json 一起落盘
    @Published private(set) var completedStepKeys: Set<String> = []
    @Published var errorMessage: String?

    private(set) var manifest: SeedManifest?

    let baseDir: URL
    let imageDir: URL

    private let recipesURL: URL
    private let stateURL: URL

    private var updatedOverrides: [Int: String] = [:]
    private var deletedIds: Set<Int> = []
    private var randomOrder: [Int] = []
    private var completedSteps: [Int: [Int]] = [:]
    private var deferredIds: Set<Int> = []
    /// 清单里标了「下次做」的菜：还留在清单里，但进开干模式时不带入
    @Published private(set) var deferredRecipeIds: Set<Int> = []

    init() {
        let fm = FileManager.default
        let appSupport = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory)
            .appendingPathComponent("RecipeBook", isDirectory: true)
        self.baseDir = appSupport
        self.imageDir = appSupport.appendingPathComponent("images", isDirectory: true)
        self.recipesURL = appSupport.appendingPathComponent("recipes.json")
        self.stateURL = appSupport.appendingPathComponent("state.json")

        try? fm.createDirectory(at: imageDir, withIntermediateDirectories: true)
        try? fm.createDirectory(
            at: imageDir.appendingPathComponent("covers", isDirectory: true), withIntermediateDirectories: true)
        try? fm.createDirectory(
            at: imageDir.appendingPathComponent("steps", isDirectory: true), withIntermediateDirectories: true)
        RecipeImageLoader.shared.setSandboxImageRoot(imageDir)

        load()
    }

    // MARK: - 加载 / 保存

    private func load() {
        // 首次启动：把 App 内置的种子数据搬到沙盒，之后读写都走沙盒
        if !FileManager.default.fileExists(atPath: recipesURL.path) {
            guard let seed = Bundle.main.url(forResource: "recipes", withExtension: "json", subdirectory: "Seed"),
                  let data = try? Data(contentsOf: seed) else {
                errorMessage = "App 里没有内置菜谱数据。"
                return
            }
            try? data.write(to: recipesURL, options: .atomic)
        }

        if let manifestURL = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Seed"),
           let manifestData = try? Data(contentsOf: manifestURL) {
            manifest = try? JSONDecoder().decode(SeedManifest.self, from: manifestData)
        }

        do {
            let data = try Data(contentsOf: recipesURL)
            var list = try JSONDecoder().decode([Recipe].self, from: data)

            let state = loadState()
            deletedIds = Set(state.deletedIds)
            updatedOverrides = state.updatedAt
            plan = state.plan
            completedSteps = state.completedSteps
            completedStepKeys = Self.completedKeys(completedSteps)
            deferredIds = Set(state.deferredIds)
            deferredRecipeIds = deferredIds

            list = list.filter { !deletedIds.contains($0.id) }
            list = list.map { recipe in
                var recipe = recipe
                if let stamp = updatedOverrides[recipe.id] { recipe.updatedAt = stamp }
                return recipe
            }
            recipes = list
            reshuffle()
        } catch {
            errorMessage = "读取本地菜谱失败：\(error.localizedDescription)"
        }
    }

    private struct PersistedState: Codable {
        var updatedAt: [Int: String]
        var deletedIds: [Int]
        var plan: [PlanItem]
        var completedSteps: [Int: [Int]]
        var deferredIds: [Int]

        private enum CodingKeys: String, CodingKey {
            case updatedAt, deletedIds, plan, completedSteps, deferredIds
        }

        init(updatedAt: [Int: String] = [:],
             deletedIds: [Int] = [],
             plan: [PlanItem] = [],
             completedSteps: [Int: [Int]] = [:],
             deferredIds: [Int] = []) {
            self.updatedAt = updatedAt
            self.deletedIds = deletedIds
            self.plan = plan
            self.completedSteps = completedSteps
            self.deferredIds = deferredIds
        }

        /// 老版本的 state.json 没有 completedSteps，逐字段兜底，别让整个 state 解码失败（会连 plan 一起丢）
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                updatedAt: try c.decodeIfPresent([Int: String].self, forKey: .updatedAt) ?? [:],
                deletedIds: try c.decodeIfPresent([Int].self, forKey: .deletedIds) ?? [],
                plan: try c.decodeIfPresent([PlanItem].self, forKey: .plan) ?? [],
                completedSteps: try c.decodeIfPresent([Int: [Int]].self, forKey: .completedSteps) ?? [:],
            deferredIds: try c.decodeIfPresent([Int].self, forKey: .deferredIds) ?? []
            )
        }
    }

    private func loadState() -> PersistedState {
        guard let data = try? Data(contentsOf: stateURL) else {
            return PersistedState()
        }
        return (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? PersistedState()
    }

    private func saveState() {
        let state = PersistedState(
            updatedAt: updatedOverrides,
            deletedIds: Array(deletedIds).sorted(),
            plan: plan,
            completedSteps: completedSteps,
            deferredIds: Array(deferredIds).sorted()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// 全量写回 recipes.json（菜谱数量级在几百，整体重写比维护增量更简单可靠）
    private func persistRecipes() {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        try? data.write(to: recipesURL, options: .atomic)
    }

    // MARK: - 查询

    func reshuffle() {
        randomOrder = recipes.map { $0.id }.shuffled()
    }

    func query(_ q: RecipeQuery) -> RecipeQueryResult {
        let tokens = q.tokens
        var list = recipes
        if !tokens.isEmpty {
            list = list.filter { TextIndex.matches($0, tokens: tokens) }
        }
        if !q.tag.isEmpty {
            let tag = q.tag
            list = list.filter { $0.tags.contains(tag) }
        }

        let randomRank = Dictionary(uniqueKeysWithValues: randomOrder.enumerated().map { ($0.element, $0.offset) })
        let sorted = list.sorted { a, b in
            if sortLess(a, b, key: q.sort, randomRank: randomRank) { return q.ascending }
            if sortLess(b, a, key: q.sort, randomRank: randomRank) { return !q.ascending }
            return a.id < b.id
        }

        // page 表示「已加载的页数」，返回的是前 page 页的**累积**结果。
        // 首页是无限滚动（滚到底就 +1 页追加），如果这里只给当前页切片，翻页时整屏内容会被替换，
        // 新的最后一项又立刻触发下一页，几步就越过最后一页变成空列表。
        let page = max(1, q.page)
        let size = max(1, q.pageSize)
        let end = min(page * size, sorted.count)
        let items = Array(sorted[0..<end])

        return RecipeQueryResult(items: items, total: sorted.count, page: page, pageSize: size)
    }

    private func sortLess(_ a: Recipe, _ b: Recipe, key: SortKey, randomRank: [Int: Int]) -> Bool {
        switch key {
        case .updated:
            return a.updatedAt < b.updatedAt
        case .collected:
            return a.collectedAt < b.collectedAt
        case .title:
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .ingredients:
            return a.ingredients.count < b.ingredients.count
        case .steps:
            return a.steps.count < b.steps.count
        case .id:
            return a.id < b.id
        case .random:
            return (randomRank[a.id] ?? Int.max) < (randomRank[b.id] ?? Int.max)
        }
    }

    func tags(limit: Int? = nil) -> [(name: String, count: Int)] {
        var counter: [String: Int] = [:]
        for recipe in recipes {
            for tag in recipe.tags where !tag.isEmpty {
                counter[tag, default: 0] += 1
            }
        }
        let all = counter
            .map { (name: $0.key, count: $0.value) }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        guard let limit else { return all }
        return Array(all.prefix(limit))
    }

    func recipe(id: Int) -> Recipe? {
        recipes.first { $0.id == id }
    }

    func hasRecipe(id: Int) -> Bool {
        recipes.contains { $0.id == id }
    }

    /// 菜谱被移出待做清单 / 从库中删除时回调（App 里接到倒计时管理器，把它的步骤倒计时一并删掉）
    var onRecipesRemovedFromPlan: (([Int]) -> Void)?

    // MARK: - 写操作

    func deleteRecipe(id: Int) {
        deletedIds.insert(id)
        let wasInPlan = plan.contains { $0.id == id }
        recipes.removeAll { $0.id == id }
        plan.removeAll { $0.id == id }
        randomOrder.removeAll { $0 == id }
        completedSteps[id] = nil
        completedStepKeys = Self.completedKeys(completedSteps)
        deferredIds.remove(id)
        deferredRecipeIds = deferredIds
        persistRecipes()
        saveState()
        if wasInPlan { onRecipesRemovedFromPlan?([id]) }
    }

    @discardableResult
    func touchRecipe(id: Int) -> Bool {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return false }
        let stamp = ISOStamp.string(from: Date())
        recipes[index].updatedAt = stamp
        updatedOverrides[id] = stamp
        persistRecipes()
        saveState()
        return true
    }

    /// 抓取写入：新菜谱插到最前，已存在的就地更新。
    ///
    /// **必须把 id 从 deletedIds 里摘掉**：以前删过的菜谱如果被重新抓回来，
    /// 删除标记还在的话，本次可见、下次冷启动 `load()` 又会被过滤掉（"重抓了却还是消失"）。
    @discardableResult
    func upsert(_ recipe: Recipe) -> (added: Bool, isNew: Bool) {
        let wasDeleted = deletedIds.remove(recipe.id) != nil

        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
            persistRecipes()
            if wasDeleted { saveState() }
            return (added: true, isNew: false)
        }
        recipes.insert(recipe, at: 0)
        randomOrder.insert(recipe.id, at: 0)
        persistRecipes()
        if wasDeleted { saveState() }
        return (added: true, isNew: true)
    }

    @discardableResult
    func addToPlan(_ recipe: Recipe) -> Bool {
        guard !plan.contains(where: { $0.id == recipe.id }) else { return false }
        let item = PlanItem(
            id: recipe.id,
            title: recipe.displayTitle,
            coverImage: recipe.coverImage,
            servings: recipe.servings,
            addedAt: ISOStamp.string(from: Date())
        )
        plan.insert(item, at: 0)
        saveState()
        return true
    }

    func removeFromPlan(id: Int) {
        guard plan.contains(where: { $0.id == id }) else { return }
        plan.removeAll { $0.id == id }
        // 菜从待做清单里移走，它的开干进度和步骤倒计时都没意义了，一并清掉
        clearCompleted(recipeId: id)
        deferredIds.remove(id)
        deferredRecipeIds = deferredIds
        saveState()
        onRecipesRemovedFromPlan?([id])
    }

    func movePlanItem(id: Int, by offset: Int) {
        guard let index = plan.firstIndex(where: { $0.id == id }) else { return }
        let next = index + offset
        guard next >= 0, next < plan.count else { return }
        plan.swapAt(index, next)
        saveState()
    }

    func clearPlan() {
        let ids = plan.map(\.id)
        plan = []
        completedSteps = [:]
        completedStepKeys = []
        deferredIds = []
        deferredRecipeIds = []
        saveState()
        onRecipesRemovedFromPlan?(ids)
    }

    // MARK: - 下次做

    func isDeferred(id: Int) -> Bool { deferredIds.contains(id) }

    /// 标记为「下次做」：留在清单里，但开干时不带入；同时清掉它这次的开干进度
    func setDeferred(id: Int, deferred: Bool) {
        if deferred {
            deferredIds.insert(id)
            completedSteps[id] = nil
            completedStepKeys = Self.completedKeys(completedSteps)
        } else {
            deferredIds.remove(id)
        }
        deferredRecipeIds = deferredIds
        saveState()
    }

    /// 进开干模式要带的菜谱：清单里标了「下次做」的不带入
    func cookPlanRecipes() -> [Recipe] {
        plan.compactMap { recipe(id: $0.id) }.filter { !deferredIds.contains($0.id) }
    }

    // MARK: - 开干模式的完成状态

    private static func completedKeys(_ map: [Int: [Int]]) -> Set<String> {
        var keys: Set<String> = []
        for (recipeId, indices) in map {
            for index in indices { keys.insert("\(recipeId)-\(index)") }
        }
        return keys
    }

    func setCompleted(recipeId: Int, stepIndex: Int, done: Bool) {
        var indices = completedSteps[recipeId] ?? []
        if done {
            guard !indices.contains(stepIndex) else { return }
            indices.append(stepIndex)
        } else {
            guard indices.contains(stepIndex) else { return }
            indices.removeAll { $0 == stepIndex }
        }
        if indices.isEmpty {
            completedSteps[recipeId] = nil
        } else {
            completedSteps[recipeId] = indices
        }
        completedStepKeys = Self.completedKeys(completedSteps)
        saveState()
    }

    func clearCompleted(recipeId: Int) {
        guard completedSteps[recipeId] != nil else { return }
        completedSteps[recipeId] = nil
        completedStepKeys = Self.completedKeys(completedSteps)
        saveState()
    }

    // MARK: - 备份 / 恢复

    func makeBackup() -> RecipeBackup {
        RecipeBackup(
            exportedAt: ISOStamp.string(from: Date()),
            recipes: recipes,
            plan: plan,
            deleted: Array(deletedIds).sorted(),
            updatedAt: updatedOverrides
        )
    }

    func backupData() throws -> Data {
        try JSONEncoder().encode(makeBackup())
    }

    struct RestoreReport {
        var updated: Int = 0
        var inserted: Int = 0
        var removed: Int = 0
        var planCount: Int = 0

        var text: String {
            "恢复完成：新增 \(inserted) 条、更新 \(updated) 条、删除 \(removed) 条，待做清单 \(planCount) 道"
        }
    }

    /// 从备份合并回本地：备份里更新的才覆盖，本地更新的保留；删除记录直接应用
    @discardableResult
    func restore(from data: Data) throws -> RestoreReport {
        let backup = try JSONDecoder().decode(RecipeBackup.self, from: data)
        var report = RestoreReport()

        var byId = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        for recipe in backup.recipes {
            if let existing = byId[recipe.id] {
                if stamp(recipe.updatedAt) >= stamp(existing.updatedAt) {
                    byId[recipe.id] = recipe
                    report.updated += 1
                }
            } else {
                byId[recipe.id] = recipe
                report.inserted += 1
            }
        }

        for id in backup.deleted {
            guard byId.removeValue(forKey: id) != nil else { continue }
            report.removed += 1
        }

        deletedIds = Set(backup.deleted)
        updatedOverrides = backup.updatedAt
        recipes = byId.values.sorted { $0.updatedAt > $1.updatedAt }
        plan = backup.plan
        report.planCount = plan.count

        reshuffle()
        persistRecipes()
        saveState()
        return report
    }

    private func stamp(_ value: String) -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
        return 0
    }

    // MARK: - 统计

    var localImageStats: (count: Int, bytes: Int) {
        let fm = FileManager.default
        var count = 0
        var bytes = 0
        if let enumerator = fm.enumerator(at: imageDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), values.isDirectory != true else { continue }
                count += 1
                bytes += values.fileSize ?? 0
            }
        }
        if let seed = Bundle.main.url(forResource: "images", withExtension: nil, subdirectory: "Seed"),
           let enumerator = fm.enumerator(at: seed, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), values.isDirectory != true else { continue }
                count += 1
                bytes += values.fileSize ?? 0
            }
        }
        return (count, bytes)
    }

    var stats: (recipes: Int, lastCollected: String?) {
        let last = recipes.map { $0.collectedAt }.max()
        return (recipes: recipes.count, lastCollected: last)
    }
}
