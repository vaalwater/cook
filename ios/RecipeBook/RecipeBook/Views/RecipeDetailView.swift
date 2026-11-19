import SwiftUI
import PhotosUI

enum RecipeDetailAction {
    case addToPlan
    case touch
    case delete
    case dismiss
}

struct RecipeDetailView: View {
    let recipe: Recipe
    let onAction: (RecipeDetailAction) -> Void

    @EnvironmentObject private var store: RecipeStore
    @Environment(\.openURL) private var openURL
    @Environment(\.openPlanTab) private var openPlanTab
    @State private var showDeleteConfirm = false
    /// 可编辑副本：编辑步骤后本地立即刷新；外部 store 变化时再同步回来
    @State private var liveRecipe: Recipe
    /// 正在编辑的步骤（非 nil 时弹出 StepEditorView）
    @State private var editingStep: RecipeStep?

    init(recipe: Recipe, onAction: @escaping (RecipeDetailAction) -> Void) {
        self.recipe = recipe
        self.onAction = onAction
        _liveRecipe = State(initialValue: recipe)
    }

    private var inPlan: Bool { store.plan.contains { $0.id == recipe.id } }

    private var totalMinutes: Double {
        liveRecipe.steps.reduce(0) { $0 + TimeEstimator.stepMinutes($1) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    description
                    tagsView
                    ingredientsSection
                    totalTimeView
                    stepsSection
                    tipsSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(liveRecipe.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // store 里的菜谱被别处改动时同步回来（如开干页/列表页编辑）
            .onChange(of: store.recipes) { _, recipes in
                if let updated = recipes.first(where: { $0.id == recipe.id }) {
                    liveRecipe = updated
                }
            }
            .sheet(item: $editingStep) { step in
                StepEditorView(recipe: liveRecipe, step: step) { text, imagePath, seconds in
                    guard store.updateStep(recipeId: recipe.id, stepIndex: step.index,
                                           text: text, image: imagePath, suggestedSeconds: seconds),
                          let updated = store.recipes.first(where: { $0.id == recipe.id }) else { return }
                    liveRecipe = updated
                }
            }
            .alert("确定删除这道菜谱？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) { onAction(.delete) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("封面图和步骤图也会一并从本地库中移除。")
            }
        }
    }

    // MARK: - 片段

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !liveRecipe.coverImage.isEmpty {
                AspectImage(path: liveRecipe.coverImage, cornerRadius: 14)
            }

            Text(liveRecipe.displayTitle)
                .font(.title2.weight(.bold))

            FlowLayout(spacing: 6) {
                // 作者名不展示：它既不是菜谱内容，混进搜索还会串味（作者叫「小土豆」→ 搜土豆命中南瓜饼）
                if !liveRecipe.servings.isEmpty { metaChip(liveRecipe.servings) }
                if !liveRecipe.favCount.isEmpty { metaChip("\(liveRecipe.favCount) 收藏") }
                metaChip("抓取于 \(Format.dateTime(liveRecipe.collectedAt))")
            }
        }
    }

    @ViewBuilder
    private var description: some View {
        if !liveRecipe.description.isEmpty {
            Text(liveRecipe.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagsView: some View {
        if !liveRecipe.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(liveRecipe.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
            }
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("用料（\(liveRecipe.ingredients.count)）")

            if liveRecipe.ingredients.isEmpty {
                Text("未抓取到用料信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if liveRecipe.ingredientGroups.main.isEmpty && liveRecipe.ingredientGroups.seasoning.isEmpty {
                ingredientList(liveRecipe.ingredients)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🍖 主料（\(liveRecipe.ingredientGroups.main.count)）")
                        .font(.subheadline.weight(.semibold))
                    ingredientList(liveRecipe.ingredientGroups.main)

                    Text("🧂 辅料（\(liveRecipe.ingredientGroups.seasoning.count)）")
                        .font(.subheadline.weight(.semibold))
                    ingredientList(liveRecipe.ingredientGroups.seasoning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ingredientList(_ items: [IngredientItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.name)
                        .font(.subheadline)
                    Spacer()
                    Text(item.amount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var totalTimeView: some View {
        if totalMinutes > 0 {
            HStack(spacing: 6) {
                Text("⏱️")
                Text("预计总时长").font(.subheadline)
                Text(TimeEstimator.format(totalMinutes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("做法（\(liveRecipe.steps.count) 步）")

            if liveRecipe.steps.isEmpty {
                Text("未抓取到步骤信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(liveRecipe.steps) { step in
                    stepRow(step)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ step: RecipeStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    let minutes = TimeEstimator.stepMinutes(step)
                    if minutes > 0 {
                        Text("⏱ \(TimeEstimator.format(minutes))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if step.suggestedSeconds > 0 {
                        Text("已手动设定")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editingStep = step
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                if !step.text.isEmpty {
                    highlightedText(step.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !step.image.isEmpty {
                    AspectImage(path: step.image, cornerRadius: 10)
                }
            }
        }
    }

    @ViewBuilder
    private var tipsSection: some View {
        if !liveRecipe.tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("小贴士")
                Text(liveRecipe.tips)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 步骤文本里的时间片段高亮（沿用旧实现 highlightStepTime 的行为）
    private func highlightedText(_ text: String) -> Text {
        StepText.segments(text).reduce(Text("")) { result, segment in
            guard segment.isTime else { return result + Text(segment.value) }
            return result + Text(segment.value).foregroundColor(.orange).fontWeight(.bold)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { onAction(.dismiss) }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            // 1. 加入待做 / 移出待做（互相切换）
            Button {
                if inPlan {
                    store.removeFromPlan(id: recipe.id)
                } else {
                    onAction(.addToPlan)
                }
            } label: {
                Label(inPlan ? "移出待做" : "待做", systemImage: inPlan ? "flame.fill" : "flame")
            }

            // 2. 进入待做清单页（关掉详情再切标签，清单页里有「开干」入口）
            Button {
                onAction(.dismiss)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { openPlanTab() }
            } label: {
                Label("待做清单", systemImage: "list.bullet")
            }

            Menu {
                Button {
                    let urlString = recipe.url.isEmpty
                        ? "https://www.xiachufang.com/recipe/\(recipe.id)/"
                        : recipe.url
                    if let url = URL(string: urlString) { openURL(url) }
                } label: {
                    Label("打开原网页", systemImage: "safari")
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("从库中删除", systemImage: "trash")
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }
}

/// 单步编辑器：文字 + 步骤图（相册选）+ 建议定时（分钟）。
/// 图片在选中时立即压缩落沙盒拿到公开路径，点「保存」时把文字/图片/秒数一起提交给 store。
struct StepEditorView: View {
    let recipe: Recipe
    let step: RecipeStep
    let onSave: (String, String?, Int) -> Void

    @EnvironmentObject private var store: RecipeStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var imagePath: String
    @State private var minutes: Int
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoError = false

    init(recipe: Recipe, step: RecipeStep, onSave: @escaping (String, String?, Int) -> Void) {
        self.recipe = recipe
        self.step = step
        self.onSave = onSave
        _text = State(initialValue: step.text)
        _imagePath = State(initialValue: step.image)
        _minutes = State(initialValue: step.suggestedSeconds > 0 ? max(1, Int(round(Double(step.suggestedSeconds) / 60.0))) : 0)
    }

    private var hasTimer: Bool { minutes > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("步骤文字") {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .font(.subheadline)
                }

                Section("步骤图片") {
                    if !imagePath.isEmpty {
                        AspectImage(path: imagePath, cornerRadius: 10)
                        Button("移除图片", role: .destructive) { imagePath = "" }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(imagePath.isEmpty ? "从相册添加图片" : "更换图片", systemImage: "photo")
                    }
                    .onChange(of: photoItem) { _, item in
                        guard let item else { return }
                        Task {
                            guard let data = try? await item.loadTransferable(type: Data.self),
                                  let uiImage = UIImage(data: data),
                                  let path = ImageDownloader.savePickedStepImage(
                                      uiImage, to: store.imageDir, recipeId: recipe.id, stepIndex: step.index
                                  ) else {
                                showPhotoError = true
                                return
                            }
                            imagePath = path
                        }
                    }
                }

                Section("建议定时") {
                    Toggle("为这一步设置建议定时", isOn: Binding(
                        get: { hasTimer },
                        set: { on in minutes = on ? max(1, minutes == 0 ? 10 : minutes) : 0 }
                    ))
                    if hasTimer {
                        HStack {
                            Text("\(minutes) 分钟")
                                .font(.system(.title3, design: .default).monospacedDigit().weight(.semibold))
                                .frame(minWidth: 90, alignment: .leading)
                            Spacer()
                            Stepper("", value: $minutes, in: 1...600, step: 1)
                                .labelsHidden()
                        }
                        HStack(spacing: 8) {
                            ForEach([1, 3, 5, 10, 20], id: \.self) { m in
                                Button("+\(m)") { minutes = min(600, minutes + m) }
                                    .font(.footnote.monospacedDigit())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                        }
                        Text("步骤文字里的时间有时解析不准，这里设定的时长会优先用于预计时间和倒计时默认值。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑第 \(step.index) 步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 图片传 nil 表示不改；移除时要把空串传下去
                        let image: String? = imagePath == step.image ? nil : imagePath
                        onSave(trimmed, image, minutes * 60)
                        dismiss()
                    }
                }
            }
            .alert("图片读取失败，请重试", isPresented: $showPhotoError) {
                Button("好", role: .cancel) {}
            }
        }
    }
}

/// 简易流式布局（标签 / 元信息一行放不下自动换行）
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
