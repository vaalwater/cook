import SwiftUI

@main
struct RecipeBookApp: App {
    @StateObject private var store: RecipeStore
    @StateObject private var scrape: ScrapeService
    /// 全局倒计时（开干模式与菜谱首页共用同一个入口）
    @StateObject private var timers: CookTimerManager

    init() {
        let store = RecipeStore()
        let scrape = ScrapeService(store: store)
        let timers = CookTimerManager()
        self._store = StateObject(wrappedValue: store)
        self._scrape = StateObject(wrappedValue: scrape)
        self._timers = StateObject(wrappedValue: timers)
        // 首次启动就申请通知权限：计时器靠本地通知在锁屏 / 后台响铃，没授权就只剩前台提示
        timers.requestNotificationPermissionIfNeeded()
        // 菜谱从待做清单里移走 / 从库中删除时，它的步骤倒计时一起清掉（连带撤销已排的到点通知）
        store.onRecipesRemovedFromPlan = { ids in
            DispatchQueue.main.async { timers.delete(recipeIds: ids) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(scrape)
                .environmentObject(timers)
        }
    }
}

/// 跨页跳转：从任意页面（比如菜谱详情）切到「待做」标签页
private struct OpenPlanTabKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openPlanTab: () -> Void {
        get { self[OpenPlanTabKey.self] }
        set { self[OpenPlanTabKey.self] = newValue }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var scrape: ScrapeService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeListView()
                .tabItem {
                    Label("菜谱", systemImage: "books.vertical")
                }
                .tag(0)

            PlanView()
                .tabItem {
                    Label("待做", systemImage: "flame")
                }
                .badge(store.plan.isEmpty ? 0 : store.plan.count)
                .tag(1)

            AchievementsView()
                .tabItem {
                    Label("成就", systemImage: "trophy")
                }
                .tag(2)

            StatsView()
                .tabItem {
                    Label("我的", systemImage: "ellipsis")
                }
                .tag(3)
        }
        .tint(.orange)
        .environment(\.openPlanTab, { selectedTab = 1 })
        .task {
            await scrape.checkSession()
        }
    }
}
