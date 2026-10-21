import SwiftUI

struct RecipeListView: View {
    @EnvironmentObject private var store: RecipeStore

    @State private var q = ""
    @State private var tag = ""
    @State private var sort: SortKey = .updated
    @State private var ascending = false
    @State private var pageSize = 24
    @State private var page = 1
    @State private var tagsExpanded = false
    @State private var selected: Recipe?
    @State private var showScrape = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var result: RecipeQueryResult {
        store.query(
            RecipeQuery(q: q, tag: tag, sort: sort, ascending: ascending, page: page, pageSize: pageSize)
        )
    }

    private let collapsedTagLimit = 40
    private var allTags: [(name: String, count: Int)] { store.tags() }
    private var shownTags: [(name: String, count: Int)] {
        tagsExpanded ? allTags : Array(allTags.prefix(collapsedTagLimit))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                tagBar
                ScrollView {
                    grid
                    footerView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $q, prompt: "搜索菜名、用料、步骤…")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showScrape) {
                ScrapeView()
            }
            .sheet(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe) { action in
                    handle(action, recipe: recipe)
                }
            }
        }
    }

    // MARK: - 顶部

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !tag.isEmpty {
                Button {
                    tag = ""
                    page = 1
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var summaryText: String {
        let r = result
        if r.total == 0 { return "没有匹配的菜谱" }
        let start = (r.page - 1) * r.pageSize + 1
        let end = min(r.page * r.pageSize, r.total)
        var text = "共 \(r.total) 道菜谱，显示第 \(start)–\(end) 条"
        if !tag.isEmpty { text += " · 标签「\(tag)」" }
        return text
    }

    private var tagBar: some View {
        Group {
            if allTags.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: 6) {
                    if tagsExpanded {
                        FlowLayout(spacing: 6) {
                            tagChips
                        }
                        .padding(.horizontal)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                tagChips
                            }
                            .padding(.horizontal)
                        }
                    }

                    if allTags.count > collapsedTagLimit {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { tagsExpanded.toggle() }
                        } label: {
                            Image(systemName: tagsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var tagChips: some View {
        ForEach(shownTags, id: \.name) { item in
            Button {
                tag = tag == item.name ? "" : item.name
                page = 1
            } label: {
                HStack(spacing: 4) {
                    Text(item.name)
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(tag == item.name ? Color.accentColor.opacity(0.9) : Color(.secondarySystemBackground))
                )
                .foregroundStyle(tag == item.name ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 网格

    private var columns: [GridItem] {
        let minimum: CGFloat = sizeClass == .regular ? 210 : 165
        return [GridItem(.adaptive(minimum: minimum), spacing: 12)]
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(result.items) { recipe in
                Button { selected = recipe } label: {
                    RecipeCard(recipe: recipe)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if recipe.id == result.items.last?.id, result.items.count < result.total {
                        page += 1
                    }
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var footerView: some View {
        if result.items.isEmpty {
            VStack(spacing: 10) {
                Text("🍳").font(.system(size: 44))
                Text("没有匹配的菜谱").font(.headline)
                Text("换个关键词，或清除标签筛选试试。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 60)
        } else if result.items.count >= result.total {
            Text("已显示全部 \(result.total) 道菜谱")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else {
            ProgressView()
                .padding(.vertical, 20)
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Image("BrandMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showScrape = true
            } label: {
                Image(systemName: "arrow.down.doc")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("排序", selection: $sort) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .pickerStyle(.inline)

                Button {
                    ascending.toggle()
                    page = 1
                } label: {
                    Label(ascending ? "升序" : "降序", systemImage: ascending ? "arrow.up" : "arrow.down")
                }

                if sort == .random {
                    Button {
                        store.reshuffle()
                        page = 1
                    } label: {
                        Label("换一批", systemImage: "shuffle")
                    }
                }

                Menu("每页数量") {
                    ForEach([12, 24, 48, 96], id: \.self) { size in
                        Button {
                            pageSize = size
                            page = 1
                        } label: {
                            if pageSize == size {
                                Label("\(size)", systemImage: "checkmark")
                            } else {
                                Text("\(size)")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
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
            page = 1
        case .delete:
            store.deleteRecipe(id: recipe.id)
            selected = nil
        case .dismiss:
            selected = nil
        }
    }
}

private struct RecipeCard: View {
    let recipe: Recipe

    private var mainPreview: String {
        recipe.ingredientGroups.main.prefix(3).map { $0.name }.joined(separator: "、")
    }

    private var seasonPreview: String {
        recipe.ingredientGroups.seasoning.prefix(3).map { $0.name }.joined(separator: "、")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RecipeImageView(
                    path: recipe.coverImage,
                    placeholderText: String(recipe.displayTitle.prefix(1)),
                    cornerRadius: 12
                )
                .frame(height: 110)
                .clipped()

                HStack(spacing: 4) {
                    if !recipe.ingredients.isEmpty {
                        badge("\(recipe.ingredients.count) 种用料")
                    }
                    if !recipe.steps.isEmpty {
                        badge("\(recipe.steps.count) 步")
                    }
                }
                .padding(6)
            }

            if !recipe.ingredientGroups.main.isEmpty || !recipe.ingredientGroups.seasoning.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !recipe.ingredientGroups.main.isEmpty {
                        ingredientLine(
                            "🍖 主料 \(recipe.ingredientGroups.main.count)" + (mainPreview.isEmpty ? "" : " · \(mainPreview)"),
                            color: .orange
                        )
                    }
                    if !recipe.ingredientGroups.seasoning.isEmpty {
                        ingredientLine(
                            "🧂 调料 \(recipe.ingredientGroups.seasoning.count)" + (seasonPreview.isEmpty ? "" : " · \(seasonPreview)"),
                            color: .secondary
                        )
                    }
                }
            }

            Text(recipe.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)

            if !recipe.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(recipe.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemBackground)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.55)))
            .foregroundStyle(.white)
    }

    private func ingredientLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
