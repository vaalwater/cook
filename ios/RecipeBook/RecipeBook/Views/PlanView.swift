import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: RecipeStore

    @State private var showCookMode = false
    @State private var showClearConfirm = false

    private var recipes: [Recipe] {
        store.plan.compactMap { store.recipe(id: $0.id) }
    }

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
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.removeFromPlan(id: item.id)
                                } label: {
                                    Label("移出", systemImage: "trash")
                                }
                            }
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
                    Button {
                        showCookMode = true
                    } label: {
                        Text("🔥 开干（\(store.plan.count) 道菜）")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
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
            }
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
