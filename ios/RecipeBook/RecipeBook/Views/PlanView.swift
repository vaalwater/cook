import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var timers: CookTimerManager

    @State private var showCookMode = false
    @State private var showClearConfirm = false
    /// 点清单里的菜谱 → 弹出这道菜的详情
    @State private var selected: Recipe?
    /// 点「完成」时的撒花事件（带按钮在页面里的位置）
    @State private var confetti: ConfettiEvent?
    /// 各行的位置，用来把撒花定位到被点「完成」的那一行左侧按钮上
    @State private var rowFrames: [Int: CGRect] = [:]

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
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .named("planRoot")), initial: true) { _, frame in
                                            DispatchQueue.main.async { rowFrames[item.id] = frame }
                                        }
                                }
                            )
                            // 完成瞬间整行泛绿，给按钮一个按下后的确认反馈
                            .overlay {
                                if confetti?.itemId == item.id {
                                    Color.green.opacity(0.18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onTapGesture {
                                selected = store.recipe(id: item.id)
                            }
                            // 右滑：先「完成」（撒花 + 记完成时间后移出清单），再「下次做」
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    complete(item)
                                } label: {
                                    Label("完成", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)

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
                            store.beginCooking(recipeIds: recipes.map { $0.id })
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
        .coordinateSpace(name: "planRoot")
        .overlay {
            if let event = confetti {
                ConfettiBurst(origin: event.origin)
                    .id(event.id)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 交互

    /// 点「完成」：先在按钮位置撒花、高亮这一行，稍后再记为完成并移出清单（让动画播完）
    private func complete(_ item: PlanItem) {
        guard confetti == nil else { return }
        let origin = rowFrames[item.id].map { CGPoint(x: $0.minX + 44, y: $0.midY) }
            ?? CGPoint(x: 60, y: 300)
        let event = ConfettiEvent(itemId: item.id, origin: origin)
        confetti = event
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.completeRecipe(id: item.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            if confetti?.id == event.id { confetti = nil }
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

private struct ConfettiEvent: Identifiable {
    let id = UUID()
    let itemId: Int
    let origin: CGPoint
}

private struct ConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let angle: Double
    let distance: CGFloat
    let size: CGSize
    let spin: Double
    let delay: Double
}

/// 「完成」按钮上炸开的彩纸：向上半圆喷出、带重力下落，尾部淡出；中心附一圈光晕和弹出的对勾
private struct ConfettiBurst: View {
    let origin: CGPoint
    @State private var progress: CGFloat = 0
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                let t = normalized(p.delay)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(p.color)
                    .frame(width: p.size.width, height: p.size.height)
                    .rotationEffect(.degrees(p.spin * t))
                    .offset(
                        x: cos(p.angle) * p.distance * t,
                        y: sin(p.angle) * p.distance * t + 180 * t * t
                    )
                    .opacity(t > 0.62 ? 1 - (t - 0.62) / 0.38 : 1)
            }

            Circle()
                .fill(Color.orange.opacity(0.35))
                .frame(width: 28, height: 28)
                .scaleEffect(1 + 4 * progress)
                .opacity(1 - Double(progress))

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
                .scaleEffect(0.4 + 0.8 * min(1, progress * 2))
                .opacity(progress > 0.55 ? 1 - (Double(progress) - 0.55) / 0.45 : 1)
        }
        .frame(width: 1, height: 1)
        .position(origin)
        .onAppear {
            particles = Self.makeParticles()
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.95)) { progress = 1 }
            }
        }
    }

    private func normalized(_ delay: Double) -> CGFloat {
        guard delay < 1 else { return 0 }
        return CGFloat(max(0, min(1, (Double(progress) - delay) / (1 - delay))))
    }

    private static func makeParticles() -> [ConfettiParticle] {
        let palette: [Color] = [.orange, .yellow, .green, .mint, .pink, .blue, .purple]
        return (0..<30).map { i in
            ConfettiParticle(
                id: i,
                color: palette.randomElement() ?? .orange,
                angle: Double.random(in: -Double.pi...0),
                distance: CGFloat.random(in: 80...220),
                size: CGSize(width: CGFloat.random(in: 5...8), height: CGFloat.random(in: 9...14)),
                spin: Double.random(in: -720...720),
                delay: Double.random(in: 0...0.15)
            )
        }
    }
}
