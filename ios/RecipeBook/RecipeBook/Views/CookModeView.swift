import SwiftUI

struct CookModeView: View {
    let recipes: [Recipe]
    /// 从别处（比如菜谱首页的倒计时列表）跳进来时，要聚焦并滚动到的步骤 key："recipeId-stepIndex"
    let focusStepKey: String?

    @Environment(\.dismiss) private var dismiss
    @State private var lanes: [CookLane]
    @State private var globalEnd: Double
    @State private var ingredients: (main: [AggregatedIngredient], seasoning: [AggregatedIngredient])
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var timers: CookTimerManager
    @State private var selectedKey: String?
    @State private var focusedStepID: String?
    @State private var showPlanManage = false
    @State private var showTimerCenter = false
    @State private var timerDraft: TimerDraft?
    @State private var firedTitle: String?
    /// 每次点卡片都 +1，保证连点同一张也能再滚一次（onChange 只认值变化）
    @State private var scrollTick = 0
    @State private var detailRecipe: Recipe?
    @State private var pendingFocusKey: String?

    /// 多道菜时给每道菜分配一个色块，食材汇总与清单里用它区分归属
    private static let palette: [Color] = [.orange, .green, .blue, .pink, .purple, .teal, .red, .indigo, .mint, .brown]

    private func colorOf(_ recipeId: Int) -> Color {
        guard let index = recipes.firstIndex(where: { $0.id == recipeId }) else { return .orange }
        return Self.palette[index % Self.palette.count]
    }

    init(recipes: [Recipe], focusStepKey: String? = nil) {
        self.recipes = recipes
        self.focusStepKey = focusStepKey
        self._pendingFocusKey = State(initialValue: focusStepKey)
        let scheduled = CookScheduler.schedule(recipes)
        self._lanes = State(initialValue: scheduled.lanes)
        self._globalEnd = State(initialValue: scheduled.globalEnd)
        self._ingredients = State(initialValue: CookScheduler.aggregate(recipes))
    }

    private var flatSteps: [FlatStep] {
        lanes.flatMap { lane in lane.steps.map { FlatStep(lane: lane, step: $0) } }
            .sorted { a, b in
                if a.step.start != b.step.start { return a.step.start < b.step.start }
                return a.step.step.index < b.step.step.index
            }
    }

    private var activeCount: Int { lanes.reduce(0) { $0 + $1.steps.filter { !$0.passive }.count } }
    private var passiveCount: Int { lanes.reduce(0) { $0 + $1.steps.filter { $0.passive }.count } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ZStack(alignment: .top) {
                    ScrollView {
                        // 不用 LazyVStack：ScrollViewReader.scrollTo 对懒加载里还没渲染的行会静默失败，
                        // 这里内容量有限，用 VStack 全量渲染换「点卡片必定能滚到位」
                        VStack(spacing: 14) {
                            summaryCard
                            ingredientCard
                            timelineCard

                            orderCard(compact: orderPinned)
                                .padding(.vertical, orderPinned ? 2 : 6)
                                .background(Color(.systemGroupedBackground))
                                .background(
                                    // SwiftUI 的 PreferenceKey/GeometryReader 在这个页面不触发，
                                    // 吸顶判定改用 UIView 层探针（读 UIScrollView 真实坐标）
                                    OrderCardProbe { cardTop, insetTop in
                                        updatePinned(cardTop: cardTop, insetTop: insetTop)
                                    }
                                )

                            stepsList
                        }
                        .padding(14)
                    }
                    .background(Color(.systemGroupedBackground))

                    // 吸顶浮层：滚过开工顺序卡片后，顶部浮一条精简版，不挤占布局
                    if orderPinned {
                        orderCard(compact: true)
                            // ZStack 会把全部可用高度提给子视图，不固定理想高度会撑满全屏
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                            .background(Color(.systemGroupedBackground).ignoresSafeArea())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .navigationTitle("开干模式")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("返回") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showTimerCenter = true
                        } label: {
                            Label(timers.timers.isEmpty ? "计时" : "\(timers.timers.count)", systemImage: "timer")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showPlanManage = true
                        } label: {
                            Label("清单 (\(store.plan.count))", systemImage: "list.bullet")
                        }
                    }
                }
                // 点开工顺序里的卡片 → 下方步骤详情滚到可见区域
                .onChange(of: selectedKey) { _, key in
                    guard let key else { return }
                    scrollToStep(key, proxy: proxy)
                }
                .onChange(of: scrollTick) { _, _ in
                    guard let key = selectedKey else { return }
                    scrollToStep(key, proxy: proxy)
                }
                // 带着步骤 key 进来（比如从首页倒计时跳过来）→ 首次出现就滚到那一步
                .onAppear {
                    guard let key = pendingFocusKey else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedKey = key
                        focusedStepID = key
                        scrollToStep(key, proxy: proxy)
                        pendingFocusKey = nil
                    }
                }
                .sheet(isPresented: $showPlanManage) {
                    CookPlanManagerView()
                        .environmentObject(store)
                }
                .sheet(isPresented: $showTimerCenter) {
                    // 点倒计时标题 → 关掉弹窗，回到开干页并聚焦到对应步骤卡片
                    CookTimerCenterView { recipeId, stepIndex in
                        showTimerCenter = false
                        let key = "\(recipeId)-\(stepIndex)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedKey = key
                            focusedStepID = key
                            scrollTick += 1
                        }
                    }
                    .environmentObject(timers)
                }
                .sheet(item: $timerDraft) { draft in
                    CookTimerSetupView(draft: draft)
                        .environmentObject(timers)
                }
                .onChange(of: timers.lastFired?.id) { _, _ in
                    firedTitle = timers.lastFired?.title
                }
                .alert("倒计时结束", isPresented: Binding(
                    get: { firedTitle != nil },
                    set: { if !$0 { firedTitle = nil } }
                )) {
                    Button("知道了") {
                        firedTitle = nil
                        timers.deleteAllFired()
                    }
                } message: {
                    Text(firedTitle ?? "")
                }
                // 清单在开干页里改动后，重新排一次时间线
                .onChange(of: store.plan.map(\.id)) { _, _ in refreshFromPlan() }
                .sheet(item: $detailRecipe) { recipe in
                    RecipeDetailView(recipe: recipe) { action in
                        if action == .dismiss { detailRecipe = nil }
                    }
                    .environmentObject(store)
                    .environmentObject(timers)
                }
            }
        }
    }

    /// 吸顶状态（带滞回，避免在阈值附近来回闪烁）：
    /// 卡片顶贴到可视区顶（差值 ≤ 8pt）开始吸顶；往回滚超过 60pt 才取消
    @State private var orderPinned = false

    private func updatePinned(cardTop: CGFloat, insetTop: CGFloat) {
        let delta = cardTop - insetTop
        if delta <= 8 {
            orderPinned = true
        } else if delta >= 60 {
            orderPinned = false
        }
    }

    /// 开工顺序里的卡片 → 定位下方对应步骤。
    /// 目标 id 带 "row-" 前缀，与 chips 的 id 区分开（否则会匹配到横向滚动条里的 chip）。
    /// 用 scrollTick 兜底：连点同一张卡片时 selectedKey 不变，onChange 不会再触发。
    private func scrollToStep(_ key: String, proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo("row-\(key)", anchor: .center) }
    }

    private func refreshFromPlan() {
        let list = store.plan.compactMap { store.recipe(id: $0.id) }
        let scheduled = CookScheduler.schedule(list)
        lanes = scheduled.lanes
        globalEnd = scheduled.globalEnd
        ingredients = CookScheduler.aggregate(list)
        selectedKey = nil
        focusedStepID = scheduled.lanes.first?.steps.first.map { key(scheduled.lanes[0], $0) }
    }

    // MARK: - 卡片

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("全部食材汇总 · 时间线 · 开工顺序", systemImage: "flame")
                    .font(.subheadline.weight(.semibold))
                Text("\(recipes.count) 道菜 · 共 \(activeCount) 个动手步骤 · \(passiveCount) 个等待步骤 · 总时长 \(TimeEstimator.format(globalEnd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ingredientCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("🥘", "全部食材汇总", "主料 / 辅料（合并去重，份数 = 用到的菜谱数）")
                if recipes.count > 1 { recipeColorLegend }
                ingredientList(title: "🍖 主料", items: ingredients.main)
                ingredientList(title: "🧂 辅料", items: ingredients.seasoning)
            }
        }
    }

    /// 多道菜时先把「菜名 ↔ 色块」对照表列出来
    private var recipeColorLegend: some View {
        FlowLayout(spacing: 6) {
            ForEach(recipes, id: \.id) { recipe in
                Button { openDetail(recipe.id) } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorOf(recipe.id))
                            .frame(width: 10, height: 10)
                        Text(recipe.displayTitle)
                            .font(.caption2)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ingredientList(title: String, items: [AggregatedIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            if items.isEmpty {
                Text("无").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.subheadline)
                        // 材料名后面标出这道菜用在哪几道菜里
                        if recipes.count > 1 {
                            ForEach(item.recipeIds, id: \.self) { recipeId in
                                Circle()
                                    .fill(colorOf(recipeId))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("× \(item.recipes) 份")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 52, alignment: .trailing)
                        Text(item.amounts.first(where: { !$0.isEmpty }).map { "参考：\($0)" } ?? " ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 96, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var timelineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    "⏱",
                    "时间线",
                    globalEnd > 0
                        ? "总耗时 \(TimeEstimator.format(globalEnd)) · 统筹调度：炖煮等待时穿插其他菜谱的工序"
                        : "没有可用步骤"
                )

                HStack(spacing: 12) {
                    legendItem(color: .orange, text: "动手步骤（占厨师）")
                    legendItem(color: .blue, text: "等待步骤（锅在炖）")
                }
                .font(.caption2)

                if globalEnd <= 0 || lanes.isEmpty {
                    Text("这些菜谱暂未抓到步骤时间，无法生成时间线。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    axisTicksView
                    ForEach(lanes) { lane in
                        laneView(lane)
                    }
                }
            }
        }
    }

    private var axisTicksView: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: geo.size.width, height: 1)
                ForEach(TimeEstimator.axisTicks(total: globalEnd), id: \.self) { tick in
                    Text(TimeEstimator.axisCompact(tick))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(x: min(geo.size.width - 30, CGFloat(tick / globalEnd) * geo.size.width))
                        .offset(y: -12)
                }
            }
        }
        .frame(height: 26)
    }

    private func laneView(_ lane: CookLane) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // 点菜名进这道菜的详情
                Button { openDetail(lane.recipeId) } label: {
                    HStack(spacing: 4) {
                        Text(lane.recipeTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                if !lane.servings.isEmpty {
                    Text(lane.servings).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(TimeEstimator.format(lane.finishAt)) 完成")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: geo.size.width, height: 18)

                    ForEach(lane.steps) { step in
                        let width = max(3, CGFloat(step.minutes / max(globalEnd, 1)) * geo.size.width)
                        let offsetX = CGFloat(step.start / max(globalEnd, 1)) * geo.size.width
                        RoundedRectangle(cornerRadius: 4)
                            .fill(step.passive ? Color.blue : Color.orange)
                            .frame(width: width, height: 18)
                            .offset(x: offsetX)
                            .opacity(selectedKey == key(lane, step) ? 1 : 0.85)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.black, lineWidth: selectedKey == key(lane, step) ? 2 : 0)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(store.completedStepKeys.contains(key(lane, step)) ? Color.green.opacity(0.75) : Color.clear)
                            )
                            .onTapGesture {
                                selectedKey = key(lane, step)
                            }
                    }
                }
            }
            .frame(height: 18)
        }
    }

    /// compact = 吸顶后的精简态：去掉卡片标题、图片与步骤说明，压缩 padding，尽量少挡下面的步骤
    private func orderCard(compact: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: compact ? 4 : 10) {
                if !compact {
                    sectionHeader("🔀", "开工顺序", orderProgressText)
                }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: compact ? 8 : 12) {
                            ForEach(Array(flatSteps.enumerated()), id: \.element.id) { index, entry in
                                orderChip(lane: entry.lane, step: entry.step, key: entry.id, index: index, compact: compact)
                                    .id(entry.id)
                            }
                        }
                        // scrollTargetLayout：让 scrollPosition(id:) 能定位到没渲染出来的远端 chip
                        .scrollTargetLayout()
                        .padding(.vertical, compact ? 2 : 10)
                    }
                    .scrollPosition(id: $focusedStepID, anchor: .center)
                    .animation(.easeOut(duration: 0.25), value: focusedStepID)
                    .onAppear {
                        focusedStepID = flatSteps.first?.id
                    }
                    .onChange(of: store.completedStepKeys) { _, _ in
                        advanceIfNeeded(proxy: proxy)
                    }
                }
            }
        }
    }

    /// 完成一步 ← 沿用旧实现 completeOrderStep：自动推进到下一个未完成的工序并居中
    private func advanceIfNeeded(proxy: ScrollViewProxy) {
        guard let index = flatSteps.firstIndex(where: { !store.completedStepKeys.contains($0.id) }) else { return }
        let target = flatSteps[index]
        selectedKey = target.id
        withAnimation(.easeOut(duration: 0.3)) {
            focusedStepID = target.id
            proxy.scrollTo(target.id, anchor: .center)
        }
    }

    private var orderProgressText: String {
        let total = flatSteps.count
        guard total > 0 else { return "暂无工序" }
        let done = flatSteps.filter { store.completedStepKeys.contains(key($0.lane, $0.step)) }.count
        if done >= total { return "🎉 全部 \(total) 个工序已完成" }
        return "已完成 \(done) / \(total) 步 · 点「完成」推进到下一步"
    }

    private func orderChip(lane: CookLane, step: ScheduledStep, key: String, index: Int, compact: Bool) -> some View {
        let done = store.completedStepKeys.contains(key)
        let scale = chipScale(index: index)
        return VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.recipeTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("步骤 \(step.step.index) · \(Int(round(step.minutes)))′")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    // 完成状态写进沙盒（退出再进来还在），同时把这一步的倒计时一起删掉
                    store.setCompleted(recipeId: lane.recipeId, stepIndex: step.step.index, done: true)
                    timers.delete(recipeId: lane.recipeId, stepIndex: step.step.index)
                } label: {
                    Text(done ? "✓ 已完成" : "完成")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(done ? .green : .accentColor)
                .disabled(done)
            }

            // 吸顶精简态：图片和步骤说明都不显示，卡片只保留「哪道菜 · 第几步 + 操作」
            if !compact, !step.step.image.isEmpty {
                RecipeImageView(path: step.step.image, placeholderText: "", cornerRadius: 8)
                    .frame(height: 110)
                    .clipped()
            }

            if !compact {
                Text(step.step.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack {
                Text(step.passive ? "等待" : "动手")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(step.passive ? Color.blue.opacity(0.15) : Color.orange.opacity(0.18)))
                Spacer()
                Text("\(TimeEstimator.axisCompact(step.start)) → \(TimeEstimator.axisCompact(step.end))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 右下角：这一步有预计时间就给一枚「计时」按钮
            if step.minutes > 0 {
                HStack {
                    Spacer(minLength: 0)
                    timerButton(lane: lane, step: step)
                }
            }
        }
        .padding(compact ? 6 : 10)
        .frame(width: compact ? 210 : 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(done ? Color.green.opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selectedKey == key ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(compact ? 1 : scale)
        .opacity(done ? 0.75 : 1)
        .animation(.easeOut(duration: 0.2), value: scale)
        .onTapGesture {
            selectedKey = key
            scrollTick += 1
            withAnimation { focusedStepID = key }
        }
    }

    /// 卡片右下角的计时按钮：没有倒计时时弹出设置窗，已有则显示剩余时间（点开进总览）
    private func timerButton(lane: CookLane, step: ScheduledStep) -> some View {
        let suggested = TimeEstimator.suggestedMinutes(for: step.step.text, fallback: step.minutes)
        let existing = timers.timer(forRecipeId: lane.recipeId, stepIndex: step.step.index)

        return Button {
            if existing != nil {
                showTimerCenter = true
            } else {
                timerDraft = TimerDraft(
                    title: timerTitle(lane: lane, step: step),
                    recipeId: lane.recipeId,
                    stepIndex: step.step.index,
                    suggestedMinutes: suggested
                )
            }
        } label: {
            if let existing {
                Label(existing.fired ? "已到点" : existing.remainingText, systemImage: existing.fired ? "bell.badge.fill" : "timer")
                    .font(.caption2.monospacedDigit())
            } else {
                Label("\(Int(round(suggested)))′ 计时", systemImage: "timer")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(existing?.fired == true ? .red : (existing != nil ? .green : .orange))
    }

    /// 倒计时标题 = 步骤精简（取第一句、去虚词，不是硬截断）；多道菜时前面补菜名
    private func timerTitle(lane: CookLane, step: ScheduledStep) -> String {
        let brief = StepText.brief(step.step.text)
        guard recipes.count > 1 else { return brief }
        return "\(lane.recipeTitle) · \(brief)"
    }

    /// 与updateOrderCardScales 同思路：离居中的卡片越远越小
    private func chipScale(index: Int) -> CGFloat {
        guard let focused = flatSteps.firstIndex(where: { $0.id == focusedStepID }) else { return 0.92 }
        let distance = abs(index - focused)
        return max(0.8, 1 - CGFloat(distance) * 0.06)
    }

    /// 步骤详情区的行模型：ForEach 的数据 id 直接就是滚动目标 id。
    /// 之前给行挂显式 `.id()` + ScrollViewReader.scrollTo 一直找不到目标（ForEach 内显式 id 不注册），
    /// 改成数据驱动 id 后 scrollTo 才生效。
    private enum StepEntry: Identifiable {
        case title(CookLane)
        case step(lane: CookLane, step: ScheduledStep)

        /// 必须与 key(lane:step:)（"\(recipeId)-\(stepIndex)"）保持同一格式
        var id: String {
            switch self {
            case .title(let lane): return "lane-\(lane.recipeId)"
            case .step(let lane, let step): return "row-\(lane.recipeId)-\(step.step.index)"
            }
        }
    }

    private var stepEntries: [StepEntry] {
        var entries: [StepEntry] = []
        for lane in lanes {
            entries.append(.title(lane))
            for step in lane.steps { entries.append(.step(lane: lane, step: step)) }
        }
        return entries
    }

    private var stepsList: some View {
        ForEach(stepEntries) { entry in
            switch entry {
            case .title(let lane):
                laneTitleRow(lane)
            case .step(let lane, let step):
                stepRow(lane, step)
            }
        }
    }

    private func laneTitleRow(_ lane: CookLane) -> some View {
        Button { openDetail(lane.recipeId) } label: {
            HStack(spacing: 4) {
                Text(lane.recipeTitle)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .id("lane-\(lane.recipeId)")
    }

    private func stepRow(_ lane: CookLane, _ step: ScheduledStep) -> some View {
        let k = key(lane, step)
        return HStack(alignment: .top, spacing: 8) {
            Text("\(step.step.index)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(store.completedStepKeys.contains(k) ? Color.green : Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(step.passive ? "等待" : "动手")
                        .font(.caption2)
                        .foregroundStyle(step.passive ? .blue : .orange)
                    Text("⏱ \(TimeEstimator.format(step.minutes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(TimeEstimator.axisCompact(step.start)) → \(TimeEstimator.axisCompact(step.end))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                highlightedText(step.step.text)
                    .font(.caption)
                if !step.step.image.isEmpty {
                    AspectImage(path: step.step.image, cornerRadius: 8)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selectedKey == k ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { selectedKey = k }
    }

    // MARK: - 工具

    /// 打开某道菜的详情（开干页里点菜名统一走这里）
    private func openDetail(_ recipeId: Int) {
        detailRecipe = recipes.first { $0.id == recipeId }
    }

    private func key(_ lane: CookLane, _ step: ScheduledStep) -> String {
        "\(lane.recipeId)-\(step.step.index)"
    }

    private func highlightedText(_ text: String) -> Text {
        StepText.segments(text).reduce(Text("")) { result, segment in
            guard segment.isTime else { return result + Text(segment.value) }
            return result + Text(segment.value).foregroundColor(.orange).fontWeight(.bold)
        }
    }

    private func sectionHeader(_ icon: String, _ title: String, _ meta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(icon)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(meta)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// 开干页里直接管理待做清单（沿用旧实现 cookPlanManage → planModal 的行为）
struct CookPlanManagerView: View {
    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.plan.isEmpty {
                    VStack(spacing: 10) {
                        Text("清单是空的")
                            .font(.headline)
                        Text("返回菜谱列表，在详情里点「待做」加菜。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(40)
                } else {
                    List {
                        ForEach(Array(store.plan.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Text(item.title).font(.subheadline)
                                Spacer()
                                Button { store.movePlanItem(id: item.id, by: -1) } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                Button { store.movePlanItem(id: item.id, by: 1) } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == store.plan.count - 1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.removeFromPlan(id: item.id) } label: {
                                    Label("移出", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("管理清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if !store.plan.isEmpty {
                        Button("清空") { store.clearPlan() }
                    }
                }
            }
        }
    }
}

/// 吸顶判定：滚动区顶部 / 开工顺序卡片顶部的屏幕坐标
/// 吸顶探针：挂在开工顺序卡片上，通过 UIView 层级找到外层 UIScrollView，
/// 每帧上报「卡片顶边在可视坐标系里的位置」和「安全区顶部内边距」。
/// 用它是因为本页面的 PreferenceKey/GeometryReader 回调不触发（iOS 17+ 未查明原因）。
struct OrderCardProbe: UIViewRepresentable {
let onChange: (_ cardTopInScrollSpace: CGFloat, _ adjustedInsetTop: CGFloat) -> Void

func makeUIView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.onChange = onChange
    return view
}

func updateUIView(_ uiView: ProbeView, context: Context) {
    uiView.onChange = onChange
}

final class ProbeView: UIView {
    var onChange: ((CGFloat, CGFloat) -> Void)?
    private var link: CADisplayLink?
    private var lastCardTop: CGFloat = .nan

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        } else if window == nil, let l = link {
            l.invalidate()
            link = nil
        }
    }

    deinit { link?.invalidate() }

    @objc private func tick() {
        guard let scroll = enclosingScrollView() else { return }
        // HostingScrollView 的 bounds.origin 与 contentOffset 不同步，convert 不可靠；
        // 改用 window 坐标：卡片顶边相对「滚动可视区顶边」再减去安全区顶部内边距
        guard let win = window else { return }
        let cardTopInWin = convert(bounds, to: win).minY
        let scrollTopInWin = scroll.convert(CGPoint(x: 0, y: scroll.contentOffset.y + scroll.adjustedContentInset.top), to: win).y
        let cardTop = cardTopInWin - scrollTopInWin
        guard lastCardTop.isNaN || abs(cardTop - lastCardTop) > 0.5 else { return }
        lastCardTop = cardTop
        onChange?(cardTop, scroll.adjustedContentInset.top)
    }

    private func enclosingScrollView() -> UIScrollView? {
        var p = superview
        while let cur = p {
            if let s = cur as? UIScrollView { return s }
            p = cur.superview
        }
        return nil
    }
}
}

struct FlatStep: Identifiable {
    let lane: CookLane
    let step: ScheduledStep

    /// 必须与详情行的 key(lane:step:) 完全一致（"\(recipeId)-\(stepIndex)"）：
    /// 之前用过 ScheduledStep.id（带 start 秒数），导致 ScrollViewReader 按这个 id
    /// 找不到下面的详情行，点卡片永远滚不过去。
    var id: String { "\(lane.recipeId)-\(step.step.index)" }
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
    }
}
