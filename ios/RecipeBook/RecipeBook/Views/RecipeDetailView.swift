import SwiftUI

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
    @State private var showDeleteConfirm = false

    private var inPlan: Bool { store.plan.contains { $0.id == recipe.id } }

    private var totalMinutes: Double {
        recipe.steps.reduce(0) { $0 + TimeEstimator.stepMinutes($1) }
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
            .navigationTitle(recipe.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
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
            if !recipe.coverImage.isEmpty {
                AspectImage(path: recipe.coverImage, cornerRadius: 14)
            }

            Text(recipe.displayTitle)
                .font(.title2.weight(.bold))

            FlowLayout(spacing: 6) {
                if !recipe.author.isEmpty { metaChip("作者：\(recipe.author)") }
                if !recipe.servings.isEmpty { metaChip(recipe.servings) }
                if !recipe.madeCount.isEmpty { metaChip("\(recipe.madeCount) 人做过") }
                if !recipe.favCount.isEmpty { metaChip("\(recipe.favCount) 收藏") }
                metaChip("抓取于 \(Format.dateTime(recipe.collectedAt))")
            }
        }
    }

    @ViewBuilder
    private var description: some View {
        if !recipe.description.isEmpty {
            Text(recipe.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tagsView: some View {
        if !recipe.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(recipe.tags, id: \.self) { tag in
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
            sectionTitle("用料（\(recipe.ingredients.count)）")

            if recipe.ingredients.isEmpty {
                Text("未抓取到用料信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if recipe.ingredientGroups.main.isEmpty && recipe.ingredientGroups.seasoning.isEmpty {
                ingredientList(recipe.ingredients)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🍖 主料（\(recipe.ingredientGroups.main.count)）")
                        .font(.subheadline.weight(.semibold))
                    ingredientList(recipe.ingredientGroups.main)

                    Text("🧂 辅料（\(recipe.ingredientGroups.seasoning.count)）")
                        .font(.subheadline.weight(.semibold))
                    ingredientList(recipe.ingredientGroups.seasoning)
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
            sectionTitle("做法（\(recipe.steps.count) 步）")

            if recipe.steps.isEmpty {
                Text("未抓取到步骤信息")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recipe.steps) { step in
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
                let minutes = TimeEstimator.stepMinutes(step)
                if minutes > 0 {
                    Text("⏱ \(TimeEstimator.format(minutes))")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
        if !recipe.tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("小贴士")
                Text(recipe.tips)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 步骤文本里的时间片段高亮（对应网页端 highlightStepTime）
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
            Button {
                onAction(.addToPlan)
            } label: {
                Label(inPlan ? "已在清单" : "待做", systemImage: inPlan ? "checkmark" : "flame")
            }
            .disabled(inPlan)

            Button {
                onAction(.touch)
            } label: {
                Label("刷新更新时间", systemImage: "arrow.clockwise")
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
