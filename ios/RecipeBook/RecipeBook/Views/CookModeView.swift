import SwiftUI

struct CookModeView: View {
    let recipes: [Recipe]

    @Environment(\.dismiss) private var dismiss
    @State private var lanes: [CookLane]
    @State private var globalEnd: Double
    @State private var ingredients: (main: [AggregatedIngredient], seasoning: [AggregatedIngredient])
    @EnvironmentObject private var store: RecipeStore
    @State private var completed: Set<String> = []
    @State private var selectedKey: String?
    @State private var focusedStepID: String?
    @State private var showPlanManage = false

    init(recipes: [Recipe]) {
        self.recipes = recipes
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    ingredientCard
                    timelineCard
                    orderCard
                    allStepsCard
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("开干模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPlanManage = true
                    } label: {
                        Label("清单 (\(store.plan.count))", systemImage: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showPlanManage) {
                CookPlanManagerView()
                    .environmentObject(store)
            }
            // 清单在开干页里改动后，重新排一次时间线
            .onChange(of: store.plan.map(\.id)) { _, _ in refreshFromPlan() }
        }
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
                ingredientList(title: "🍖 主料", items: ingredients.main)
                ingredientList(title: "🧂 辅料", items: ingredients.seasoning)
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
                Text(lane.recipeTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
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
                                    .fill(completed.contains(key(lane, step)) ? Color.green.opacity(0.75) : Color.clear)
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

    private var orderCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("🔀", "开工顺序", orderProgressText)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(flatSteps.enumerated()), id: \.element.id) { index, entry in
                                orderChip(lane: entry.lane, step: entry.step, key: entry.id, index: index)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollPosition(id: $focusedStepID, anchor: .center)
                    .animation(.easeOut(duration: 0.25), value: focusedStepID)
                    .onAppear {
                        focusedStepID = flatSteps.first?.id
                    }
                    .onChange(of: completed) { _, _ in
                        advanceIfNeeded(proxy: proxy)
                    }
                }
            }
        }
    }

    /// 完成一步 ← 沿用旧实现 completeOrderStep：自动推进到下一个未完成的工序并居中
    private func advanceIfNeeded(proxy: ScrollViewProxy) {
        guard let index = flatSteps.firstIndex(where: { !completed.contains($0.id) }) else { return }
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
        let done = flatSteps.filter { completed.contains(key($0.lane, $0.step)) }.count
        if done >= total { return "🎉 全部 \(total) 个工序已完成" }
        return "已完成 \(done) / \(total) 步 · 点「完成」推进到下一步"
    }

    private func orderChip(lane: CookLane, step: ScheduledStep, key: String, index: Int) -> some View {
        let done = completed.contains(key)
        let scale = chipScale(index: index)
        return VStack(alignment: .leading, spacing: 8) {
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
                    completed.insert(key)
                } label: {
                    Text(done ? "✓ 已完成" : "完成")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(done ? .green : .accentColor)
                .disabled(done)
            }

            if !step.step.image.isEmpty {
                RecipeImageView(path: step.step.image, placeholderText: "", cornerRadius: 8)
                    .frame(height: 110)
                    .clipped()
            }

            Text(step.step.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

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
        }
        .padding(10)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(done ? Color.green.opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selectedKey == key ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(scale)
        .opacity(done ? 0.75 : 1)
        .animation(.easeOut(duration: 0.2), value: scale)
        .onTapGesture {
            selectedKey = key
            withAnimation { focusedStepID = key }
        }
    }

    /// 与updateOrderCardScales 同思路：离居中的卡片越远越小
    private func chipScale(index: Int) -> CGFloat {
        guard let focused = flatSteps.firstIndex(where: { $0.id == focusedStepID }) else { return 0.92 }
        let distance = abs(index - focused)
        return max(0.8, 1 - CGFloat(distance) * 0.06)
    }

    private var allStepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("📖", "全部步骤详情", "点击上方时间线块可在下方定位")

                ForEach(lanes) { lane in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lane.recipeTitle)
                            .font(.subheadline.weight(.semibold))
                        ForEach(lane.steps) { step in
                            let k = key(lane, step)
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(step.step.index)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(completed.contains(k) ? Color.green : Color.accentColor))

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
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedKey == k ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                            .onTapGesture { selectedKey = k }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 工具

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

struct FlatStep: Identifiable {
    let lane: CookLane
    let step: ScheduledStep

    var id: String { "\(lane.recipeId)-\(step.id)" }
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
