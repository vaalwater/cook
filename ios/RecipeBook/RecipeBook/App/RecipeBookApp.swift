import SwiftUI

@main
struct RecipeBookApp: App {
    @StateObject private var store: RecipeStore
    @StateObject private var scrape: ScrapeService

    init() {
        let store = RecipeStore()
        self._store = StateObject(wrappedValue: store)
        self._scrape = StateObject(wrappedValue: ScrapeService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(scrape)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var scrape: ScrapeService

    var body: some View {
        TabView {
            RecipeListView()
                .tabItem {
                    Label("菜谱", systemImage: "books.vertical")
                }

            PlanView()
                .tabItem {
                    Label("待做", systemImage: "flame")
                }
                .badge(store.plan.isEmpty ? 0 : store.plan.count)

            StatsView()
                .tabItem {
                    Label("我的", systemImage: "ellipsis")
                }
        }
        .tint(.orange)
        .task {
            await scrape.checkSession()
        }
    }
}
