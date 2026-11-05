import SwiftUI

/// 成就页：记录「待做」清单里被「完成」的菜，统计今天 / 本周做了哪些、各用了多少时间。
/// 用时 = 点「开干」到该道菜被「完成」的间隔（由 RecipeStore 在 completeRecipe 时算出）。
struct AchievementsView: View {
    @EnvironmentObject private var store: RecipeStore

    /// 顶部随机鼓励语（进入页面时抽一条）
    @State private var cheer: String = ""
    /// 点成就记录 → 打开这道菜的详情
    @State private var selected: Recipe?
    /// 菜谱已从库中删除时，点记录给出说明而不是毫无反应
    @State private var missingTitle: String?

    private var sorted: [CookCompletion] {
        store.completions.sorted { $0.completedAt > $1.completedAt }
    }

    private var today: [CookCompletion] {
        sorted.filter { Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.completedAt)) }
    }

    private var week: [CookCompletion] {
        let weekStart = Self.weekStart()
        return sorted.filter {
            let d = Date(timeIntervalSince1970: $0.completedAt)
            return d >= weekStart && !Calendar.current.isDateInToday(d)
        }
    }

    private var earlier: [CookCompletion] {
        let weekStart = Self.weekStart()
        return sorted.filter { Date(timeIntervalSince1970: $0.completedAt) < weekStart }
    }

    private var weekCount: Int { today.count + week.count }
    private var todayDuration: Double { today.reduce(0) { $0 + $1.duration } }
    private var weekDuration: Double { (today + week).reduce(0) { $0 + $1.duration } }

    /// 本周首次完成的菜数：本周完成的菜里，在周一起点之前从没完成过的
    private var newDishesThisWeek: Int {
        let start = Self.weekStart().timeIntervalSince1970
        let before = Set(store.completions.filter { $0.completedAt < start }.map { $0.recipeId })
        let thisWeek = Set((today + week).map { $0.recipeId })
        return thisWeek.subtracting(before).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    emptyState
                } else {
                    List {
                        cheerSection
                        summarySection
                        groupSection("今天", items: today)
                        if !week.isEmpty { groupSection("本周", items: week) }
                        if !earlier.isEmpty { groupSection("更早", items: earlier) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("成就")
            .onAppear { rollCheer() }
            .sheet(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe) { action in
                    handle(action, recipe: recipe)
                }
                .environmentObject(store)
            }
            .alert(
                "菜谱已不在库中",
                isPresented: Binding(
                    get: { missingTitle != nil },
                    set: { if !$0 { missingTitle = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("「\(missingTitle ?? "")」已从菜谱库移除，成就记录仍保留。")
            }
        }
    }

    // MARK: - 点击记录打开菜谱

    private func open(_ c: CookCompletion) {
        if let recipe = store.recipe(id: c.recipeId) {
            selected = recipe
        } else {
            missingTitle = c.title
        }
    }

    private func handle(_ action: RecipeDetailAction, recipe: Recipe) {
        switch action {
        case .addToPlan:
            store.addToPlan(recipe)
        case .touch:
            store.touchRecipe(id: recipe.id)
            selected = nil
        case .delete:
            store.deleteRecipe(id: recipe.id)
            selected = nil
        case .dismiss:
            selected = nil
        }
    }

    // MARK: - 鼓励语

    private func rollCheer() {
        cheer = Self.makeCheer(
            isEmpty: sorted.isEmpty,
            todayCount: today.count,
            weekCount: weekCount,
            newDishes: newDishesThisWeek
        )
    }

    private static func makeCheer(isEmpty: Bool, todayCount: Int, weekCount: Int, newDishes: Int) -> String {
        if isEmpty {
            return [
                "从下一道菜开始，积累你的厨房成就吧",
                "先挑一道想吃的放进待做清单，开干等你",
                "还没开火？去菜谱库逛逛，说不定就有想做的",
            ].randomElement() ?? "从下一道菜开始，积累你的厨房成就吧"
        }

        var pool: [String] = []
        if todayCount > 0 {
            pool += [
                "今天又做了\(todayCount)道菜，很棒呀！",
                "今天\(todayCount)道菜出锅，饱腹又治愈～",
                "今天亲手做了\(todayCount)道菜，给生活的诚意满分",
                "灶台有动静，今天\(todayCount)道菜已经到手",
            ]
        }
        if weekCount > 0 {
            pool += [
                "这周已经做了\(weekCount)道菜，节奏在线",
                "这周\(weekCount)道菜到手，继续保持",
            ]
        }
        if newDishes > 0 {
            pool += [
                "这周尝试了\(newDishes)道新菜，生活有滋有味",
                "新菜上手，这周又多\(newDishes)道拿手好菜",
            ]
        }
        if pool.isEmpty {
            pool += ["记录你的每一道菜，成就慢慢攒起来", "待做清单里挑一道，今天开个火"]
        }
        return pool.randomElement() ?? pool[0]
    }

    private var cheerSection: some View {
        Section {
            Text(cheer)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 4)
        }
    }

    // MARK: - 概览

    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                tile("今天", count: today.count, duration: todayDuration)
                Divider().frame(height: 46)
                tile("本周", count: weekCount, duration: weekDuration)
            }
            .frame(height: 72)
        }
    }

    private func tile(_ title: String, count: Int, duration: Double) -> some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.title2.weight(.bold)).foregroundStyle(.orange)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Self.formatDuration(duration)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 分组列表

    private func groupSection(_ title: String, items: [CookCompletion]) -> some View {
        Section {
            ForEach(items) { c in
                let exists = store.hasRecipe(id: c.recipeId)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(Self.formatCompletedAt(c.completedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(c.duration > 0 ? Self.formatDuration(c.duration) : "未计时")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(c.duration > 0 ? .primary : .secondary)
                        if exists {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary.opacity(0.5))
                        } else {
                            Text("已移除")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { open(c) }
            }
        } header: {
            Text(title)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🏆").font(.system(size: 44))
            Text("还没有完成的菜")
                .font(.headline)
            Text("在「待做」清单里右滑某道菜点「完成」，这里会记录今天和本周做过的菜以及用时。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(cheer)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - 工具

    /// 本周起点：周一 00:00（不随系统区域设置的每周首日变化）
    private static func weekStart() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // weekday: 1=周日 2=周一 ... 7=周六；换算成距本周周一的天数
        let daysSinceMonday = (cal.component(.weekday, from: today) + 5) % 7
        return cal.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    static func formatDuration(_ seconds: Double) -> String {
        let t = Int(max(0, seconds))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    static func formatCompletedAt(_ epoch: Double) -> String {
        let d = Date(timeIntervalSince1970: epoch)
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(d) {
            fmt.dateFormat = "HH:mm"
        } else if cal.isDateInYesterday(d) {
            fmt.dateFormat = "昨天 HH:mm"
        } else {
            fmt.dateFormat = "M月d日 HH:mm"
        }
        return fmt.string(from: d)
    }
}
