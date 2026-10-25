import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var timers: CookTimerManager

    @State private var showCookMode = false
    @State private var showClearConfirm = false
    /// 点清单里的菜谱 → 弹出这道菜的详情
    @State private var selected: Recipe?

    private var recipes: [Recipe] { store.cookPlanRecipes() }
    private var deferredCount: Int { store.deferredRecipeIds.count }

    var body: some View {
        NavigationStack {
            Group {
                if store.plan.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(store.plan.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                RecipeImageView(
                                    path: item.coverImage,
                                    placeholderText: String(item.title.prefix(1)),
                                    cornerRadius: 8
                                )
                                .frame(width: 56, height: 56)

                                VStack(alignment: .leading, spacing: 2) {
                                    if store.isDeferred(id: item.id) {
                                        Text("下次做 · \(item.title)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    } else {
                                        Text(item.title)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(2)
                                    }
                                    if !item.servings.isEmpty {
                                        Text(item.servings)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 4)

                                HStack(spacing: 2) {
                                    moveButton("chevron.up", enabled: index > 0) {
                                        store.movePlanItem(id: item.id, by: -1)
                                    }
                                    moveButton("chevron.down", enabled: index < store.plan.count - 1) {
                                        store.movePlanItem(id: item.id, by: 1)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = store.recipe(id: item.id)
                            }
                            // 右滑：设为「下次做」（还在清单里，但开干时不带入）
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    store.setDeferred(id: item.id, deferred: !store.isDeferred(id: item.id))
                                } label: {
                                    Label(
                                        store.isDeferred(id: item.id) ? "本次做" : "下次做",
                                        systemImage: store.isDeferred(id: item.id) ? "flame" : "moon.zzz"
                                    )
                                }
                                .tint(store.isDeferred(id: item.id) ? .orange : .indigo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.removeFromPlan(id: item.id)
                                } label: {
                                    Label("移出", systemImage: "trash")
                                }
                            }
                            // 标了「下次做」的行整体压一层灰，跟本次要做的区分开
                            .listRowBackground(
                                ZStack {
                                    Color(.secondarySystemGroupedBackground)
                                    if store.isDeferred(id: item.id) {
                                        Color.primary.opacity(0.08)
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("待做清单")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.plan.isEmpty {
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Label("清空", systemImage: "trash")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.plan.isEmpty {
                    VStack(spacing: 4) {
                        if deferredCount > 0 {
                            Text("已留 \(deferredCount) 道到下次（右滑可改回本次做）")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showCookMode = true
                        } label: {
                            Text(recipes.isEmpty ? "都安排到下次了" : "🔥 开干（\(recipes.count) 道菜）")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(recipes.isEmpty)
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .confirmationDialog("确定清空待做清单？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.clearPlan() }
                Button("取消", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCookMode) {
                CookModeView(recipes: recipes)
                    .environmentObject(store)
                    .environmentObject(timers)
            }
            .sheet(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe) { action in
                    handle(action, recipe: recipe)
                }
            }
        }
    }

    // MARK: - 交互

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

    private func moveButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? Color.orange : Color.secondary.opacity(0.35))
                .frame(width: 28, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📋").font(.system(size: 44))
            Text("清单是空的")
                .font(.headline)
            Text("在菜谱详情里点「🔥 待做」，凑齐几道菜就能一起统筹开工。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
