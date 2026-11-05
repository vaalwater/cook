import SwiftUI
import Speech
import AVFoundation
import UIKit

struct RecipeListView: View {
    @FocusState private var searchFocused: Bool
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var timers: CookTimerManager

    @State private var q = ""
    @State private var tag = ""
    @State private var sort: SortKey = .updated
    @State private var ascending = false
    @State private var pageSize = 24
    @State private var page = 1
    @State private var tagsExpanded = false
    @State private var selected: Recipe?
    @State private var showScrape = false
    @State private var showTimers = false
    @State private var showCookMode = false
    @State private var cookRecipes: [Recipe] = []
    @State private var focusStepKey: String?
    /// 最近搜索：数组顺序就是时间倒序（最新的在最前）
    @State private var searchHistory: [String] = []
    /// 语音输入状态
    @StateObject private var speech = SpeechRecognizer()
    @State private var showSpeechDenied = false
    /// 是否正按住麦克风：按住期间锁定顶部栏为“聚焦/宽”外观，避免 TextField 因点到麦克风而失焦、
    /// 导致布局在宽窄间抖动、松手时 onEnded 打不到麦克风而卡在录音。
    @State private var pressingMic = false

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var result: RecipeQueryResult {
        store.query(
            RecipeQuery(q: q, tag: tag, sort: sort, ascending: ascending, page: page, pageSize: pageSize)
        )
    }

    private let collapsedTagLimit = 40
    /// 展开后标签区最多占的高度（约 5 行：每行约 30pt + 6pt 间距）
    private let expandedTagBarHeight: CGFloat = 180
    private var allTags: [(name: String, count: Int)] { store.tags() }
    private var shownTags: [(name: String, count: Int)] {
        tagsExpanded ? allTags : Array(allTags.prefix(collapsedTagLimit))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                // 搜索条下方的内容区（麦克风在上面的 topBar 里，结构上不会被下面的手势影响）
                VStack(spacing: 0) {
                    summaryBar
                    // 搜索进行中（点开搜索框或已经输入）就把标签筛选区收起来，给搜索结果腾地方
                    if !searchFocused && q.isEmpty {
                        tagBar
                    }
                    ScrollView {
                        // 点开搜索框还没输入时：内容区换成最近搜索列表；一输入就回到正常结果
                        if searchFocused, q.isEmpty, !searchHistory.isEmpty {
                            recentSearchList
                        } else {
                            grid
                            footerView
                        }
                    }
                }
                // 搜索框聚焦时：点内容区任意处或滚动即失焦（搜索条缩回、文字保留）。
                // 挂在 ScrollView 的父视图上用 simultaneousGesture：空白/滚动处能触发失焦，
                // 又不会像覆盖层那样挡住下方按钮——最近搜索词、菜谱卡片等仍可正常点按（同时失焦）。
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in if searchFocused { searchFocused = false } }
                )
            }
            .background(Color(.systemGroupedBackground))
            .animation(.easeOut(duration: 0.18), value: searchFocused)
            .animation(.easeOut(duration: 0.18), value: q.isEmpty)
            .navigationBarHidden(true)
            .onAppear {
                searchHistory = UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? []
            }
            // 语音识别的实时文字直接填进搜索框；权限被拒时弹提示
            .onReceive(speech.$transcript) { q = $0 }
            .onReceive(speech.$authorizationDenied) { denied in
                if denied { showSpeechDenied = true }
            }
            // 筛选条件一变就回到第一页（分页是累积的，不重置会带着旧页数加载一堆）
            .onChange(of: q) { _, _ in page = 1 }
            .onChange(of: sort) { _, _ in page = 1 }
            .onChange(of: store.recipes.count) { _, _ in page = 1 }
            .sheet(isPresented: $showScrape) {
                ScrapeView()
                    .environmentObject(timers)
            }
            .sheet(isPresented: $showTimers) {
                // 点倒计时标题 → 进开干页并聚焦到那一步（菜谱不在清单里就先加进去）
                CookTimerCenterView { recipeId, stepIndex in
                    openCookMode(recipeId: recipeId, stepIndex: stepIndex)
                }
                .environmentObject(timers)
            }
            .fullScreenCover(isPresented: $showCookMode) {
                CookModeView(recipes: cookRecipes, focusStepKey: focusStepKey)
                    .environmentObject(store)
                    .environmentObject(timers)
            }
            .sheet(item: $selected) { recipe in
                RecipeDetailView(recipe: recipe) { action in
                    handle(action, recipe: recipe)
                }
            }
            .alert("无法使用语音输入", isPresented: $showSpeechDenied) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在设置中允许「菜谱小本本」使用语音识别和麦克风。")
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
        var text = "共 \(r.total) 道菜谱，已显示 1–\(r.items.count) 条"
        if !tag.isEmpty { text += " · 标签「\(tag)」" }
        return text
    }

    private var tagBar: some View {
        Group {
            if allTags.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: 6) {
                    tagsArea

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

    /// 折叠时横向滑一行；展开后换行铺最多 5 行，超出的在固定高度里自己滚。
    /// 注意：展开态必须用固定高度 + 内部滚动，否则几百个标签会把下面的列表整个顶出屏幕。
    @ViewBuilder
    private var tagsArea: some View {
        if tagsExpanded {
            ScrollView([.vertical], showsIndicators: true) {
                FlowLayout(spacing: 6) {
                    tagChips
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
            .frame(height: expandedTagBarHeight)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagChips
                }
                .padding(.horizontal)
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

    // MARK: - 搜索历史

    private static let historyKey = "recipeSearchHistory"
    /// 按时间倒序保留最近多少条
    private static let historyLimit = 15

    /// 点开搜索框、还没输入时，内容区显示的最近搜索列表
    private var recentSearchList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("最近搜索")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("清空") { clearHistory() }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
            }
            .padding(.bottom, 6)

            ForEach(searchHistory, id: \.self) { term in
                Button {
                    q = term
                    rememberSearch(term)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(term)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding()
    }

    /// 记一条搜索词：自动去重、插到最前、超出上限的丢掉（数组顺序 = 时间倒序）
    private func rememberSearch(_ text: String) {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var list = searchHistory.filter { $0 != term }
        list.insert(term, at: 0)
        if list.count > Self.historyLimit { list = Array(list.prefix(Self.historyLimit)) }
        searchHistory = list
        UserDefaults.standard.set(list, forKey: Self.historyKey)
    }

    private func clearHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
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

    // MARK: - 顶部栏

    /// 自绘顶部栏：未聚焦 = [App图标][搜索框][定时器…]，搜索框夹在中间；
    /// 聚焦（或正按住麦克风）时隐藏两侧图标 → 搜索框（maxWidth 撑开）拉满整行。
    private var topBar: some View {
        let wide = searchFocused || pressingMic
        return HStack(spacing: 8) {
            if !wide { leadingBrand }
            searchBar
                .frame(maxWidth: wide ? .infinity : UIScreen.main.bounds.width * 0.46)
            if !wide {
                Spacer(minLength: 0)
                trailingButtons
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    private var leadingBrand: some View {
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

    /// 右侧一组图标（定时器 / 导入 / 排序），间距收紧
    private var trailingButtons: some View {
        HStack(spacing: 16) {
            Button {
                showTimers = true
            } label: {
                TimerToolbarLabel(
                    count: timers.timers.count,
                    hasFired: timers.timers.contains { $0.fired }
                )
                .imageScale(.large)
            }

            Button {
                showScrape = true
            } label: {
                Image(systemName: "arrow.down.doc")
                    .imageScale(.large)
            }

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
                    .imageScale(.large)
            }
        }
    }

    /// 自绘搜索栏：搜索框右侧放麦克风，按住说话、松手完成（语音转文字直接进搜索词）
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField(speech.isRecording ? "" : "搜索菜名、用料、步骤…", text: $q)
                .onSubmit { rememberSearch(q) }
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !q.isEmpty {
                Button {
                    q = ""
                    page = 1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            micButton
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                Capsule().fill(speech.isRecording ? Color.orange.opacity(0.18) : Color(.secondarySystemBackground))
                // 录音时整条搜索框铺一层跳动的声波底纹（颜色加深）
                if speech.isRecording {
                    WaveformBackdrop()
                        .clipShape(Capsule())
                }
            }
        )
    }

    /// 麦克风按钮：按住开始识别（图标变红 + 放大），松手结束并把识别结果留在搜索框
    private var micButton: some View {
        Image(systemName: speech.isRecording ? "waveform" : "mic")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(speech.isRecording ? .red : .secondary)
            .frame(width: 30, height: 30)
            .scaleEffect(speech.isRecording ? 1.15 : 1)
            .animation(.easeInOut(duration: 0.15), value: speech.isRecording)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        pressingMic = true
                        searchFocused = true
                        speech.start(with: q)
                    }
                    .onEnded { _ in
                        pressingMic = false
                        speech.stop()
                        searchFocused = true
                    }
            )
    }

    /// 录音时的搜索框底纹：一排上下跳动的竖条，做出"声波"质感（颜色加深，更明显）
    private struct WaveformBackdrop: View {
        @State private var animate = false
        private let heights: [CGFloat] = [8, 14, 6, 16, 10, 7, 13, 9, 15, 6, 12, 8, 14, 7, 11, 9, 13, 6, 15, 8]
        var body: some View {
            HStack(spacing: 3) {
                ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 2.5, height: h)
                        .scaleEffect(y: animate ? 1 : 0.45, anchor: .center)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.04),
                            value: animate
                        )
                }
            }
            .opacity(0.6)
            .onAppear { animate = true }
        }
    }

    // MARK: - 交互

    /// 从倒计时跳进开干页面：这道菜已在清单里就带上整个清单，否则只做这一道；并聚焦到对应步骤
    private func openCookMode(recipeId: Int, stepIndex: Int) {
        showTimers = false
        guard let recipe = store.recipe(id: recipeId) else { return }
        let inPlan = store.plan.contains { $0.id == recipeId }
        if !inPlan {
            store.addToPlan(recipe)
            cookRecipes = [recipe]
        } else {
            // 这道菜要是被标了「下次做」，点它的倒计时就把它拉回本次做，否则跳过去找不到它
            if store.isDeferred(id: recipeId) { store.setDeferred(id: recipeId, deferred: false) }
            cookRecipes = store.cookPlanRecipes()
        }
        focusStepKey = "\(recipeId)-\(stepIndex)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCookMode = true }
    }

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

/// 按住说话、松手结束的语音识别：识别到的文字实时通过 `transcript` 暴露，视图直接填进搜索框。
///
/// 关键点（参考 chemiistryApp 的语音实现）：
/// ① 松手后只调用 `request.endAudio()`，把麦克风关掉，但**不要立刻 cancel 任务**——
///    要让识别引擎把"最终结果"返回来（handler 里 `isFinal` 时再收尾），否则只拿到最后一个
///    中间结果（比如"红烧肉"只识别出"红"）。
/// ② 万一最终结果迟迟不来（网络/无语音），用兜底定时器强制收尾。
private final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var authorizationDenied = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()
    /// 松手后的兜底收尾定时器：最终结果没回来时强制结束
    private var finishItem: DispatchWorkItem?
    /// 开始录音前搜索框里已有的文字：语音识别结果要**追加**到它后面，而不是替换
    private var prefix = ""

    /// 申请语音识别 + 麦克风权限（两者都授权才算通过）
    private func ensurePermission(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var speechOK = false
        var micOK = false

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechOK = true
        case .notDetermined:
            group.enter()
            SFSpeechRecognizer.requestAuthorization { status in
                speechOK = status == .authorized
                group.leave()
            }
        default:
            speechOK = false
        }

        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            micOK = true
        case .undetermined:
            group.enter()
            session.requestRecordPermission { granted in
                micOK = granted
                group.leave()
            }
        default:
            micOK = false
        }

        group.notify(queue: .main) {
            let ok = speechOK && micOK && self.recognizer != nil
            if !ok { self.authorizationDenied = true }
            completion(ok)
        }
    }

    /// base：开始录音前搜索框里已有的文字。识别结果会追加在它后面。
    func start(with base: String) {
        guard !isRecording else { return }
        prefix = base.trimmingCharacters(in: .whitespacesAndNewlines)
        ensurePermission { [weak self] ok in
            guard ok else { return }
            self?.beginCapture()
        }
    }

    private func beginCapture() {
        // 收掉上一次可能残留的收尾定时器
        finishItem?.cancel()
        finishItem = nil

        task?.cancel(); task = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)

        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord 比 record 在语音识别场景下兼容性更好；defaultToSpeaker 避免录音时外放被压
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            authorizationDenied = true
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 关掉"仅设备端"，中文走苹果服务端识别更准
        request.requiresOnDeviceRecognition = false
        self.request = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            cleanup()
            authorizationDenied = true
            return
        }

        transcript = prefix
        isRecording = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.isRecording else { return }
            if let result {
                // 边听边出字：实时填进搜索框；已有文字作为前缀，识别结果追加在后面而非替换
                let text = result.bestTranscription.formattedString
                let pre = self.prefix.isEmpty ? "" : self.prefix + " "
                self.transcript = pre + text
                if result.isFinal {
                    self.cleanup()
                }
            } else if error != nil {
                // 无语音 / 网络不通等：收尾（transcript 保留已识别到的部分）
                self.cleanup()
            }
        }
    }

    /// 松手：关掉麦克风，等识别把"修正后的完整结果"交上来；兜底 1.2s 强制收尾
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        finishItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.cleanup() }
        finishItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    /// 停止音频管线、撤销 AVAudioSession（幂等，可重复调用）。
    /// 先置 isRecording=false，避免 cancel 触发的 error 回调再次进入 handler 造成重入。
    private func cleanup() {
        finishItem?.cancel()
        finishItem = nil
        isRecording = false
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
