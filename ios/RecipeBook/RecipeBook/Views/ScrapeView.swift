import SwiftUI

/// 手机上直接抓菜谱：粘贴下厨房菜谱 ID 或 URL（每行一个），App 自己抓页面、自己解析、自己存图。
struct ScrapeView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var scrape: ScrapeService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var input = ""
    @State private var withImages = true
    @State private var forceUpdate = false
    @State private var showLogin = false
    @State private var showClearSession = false

    private let maxBatch = ScrapeOptions().maxBatch
    private var ids: [String] { Array(ScrapeService.parseIDs(input).prefix(maxBatch)) }
    private var rawCount: Int { ScrapeService.parseIDs(input).count }

    var body: some View {
        NavigationStack {
            Form {
                Section { sessionContent } header: { Text("登录态") }
                Section { inputOrQueue } header: { Text("菜谱 ID / 链接") }
                Section { optionsContent } header: { Text("选项") }
                Section { progressContent } header: { Text("进度") }
            }
            .navigationTitle("抓取菜谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(startURL: Self.probeURL(first: ids.first)) { cookies in
                    scrape.finishLogin(cookies: cookies)
                } onCancel: {
                    scrape.cancelLogin()
                }
            }
            .onChange(of: scrape.status) { _, status in
                if case .waitingLogin = status { showLogin = true }
            }
            // App 进入后台会被系统挂起，网络请求随之停住；回前台才继续。提前告诉用户，别以为是卡死。
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, scrape.isRunning { scrape.noteBackgrounded() }
            }
            .alert("确定清除登录态？", isPresented: $showClearSession) {
                Button("清除", role: .destructive) {
                    SessionStore.clear()
                    scrape.sessionReady = false
                    scrape.sessionMessage = "未登录"
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    static var siteURL: URL {
        URL(string: SessionStore.baseURL) ?? URL(string: "https://www.xiachufang.com")!
    }

    static func probeURL(first: String?) -> URL {
        let url = String(format: SessionStore.recipeURLTemplate, first ?? "106125193")
        return URL(string: url) ?? URL(string: SessionStore.baseURL)!
    }

    // MARK: - 分区内容

    private var sessionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(scrape.sessionReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(scrape.sessionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await scrape.checkSession() }
                } label: {
                    Label("检查", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }

            Button { showLogin = true } label: {
                Label("登录下厨房 / 过滑块验证", systemImage: "person.badge.key")
            }

            Button(role: .destructive) { showClearSession = true } label: {
                Label("清除登录态", systemImage: "trash")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 没开始抓取时是输入框 + 下载按钮；一旦开始，原输入区变成每条一行的状态列表
    private var inputOrQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scrape.items.isEmpty {
                inputContent
                downloadButton
            } else {
                queueContent
            }
        }
    }

    private var downloadButton: some View {
        HStack {
            Button {
                scrape.start(
                    input: input,
                    options: ScrapeOptions(withImages: withImages, forceUpdate: forceUpdate)
                )
            } label: {
                Label("下载", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(scrape.isRunning || ids.isEmpty)
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 0)
        }
    }

    private var queueContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(scrape.items) { item in
                HStack(alignment: .top, spacing: 8) {
                    // 进行中的图标一直转，避免看起来像卡住
                    Group {
                        if item.state == .running {
                            SpinningIcon(
                                systemName: Self.iconName(for: item.state),
                                color: Self.iconColor(for: item.state)
                            )
                        } else {
                            Image(systemName: Self.iconName(for: item.state))
                                .font(.subheadline)
                                .foregroundStyle(Self.iconColor(for: item.state))
                        }
                    }
                    .frame(width: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "菜谱 \(item.id)")
                            .font(.footnote)
                        if let message = item.message, !message.isEmpty {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            // 「停止抓取」在下面的进度区已经有一个，这里只在结束后给回退入口
            if !scrape.isRunning {
                Button { scrape.reset() } label: {
                    Label("重新输入菜谱 ID", systemImage: "pencil")
                        .font(.subheadline)
                }
            }
        }
    }

/// 匀速旋转的小图标（只给「进行中」用）
private struct SpinningIcon: View {
    let systemName: String
    let color: Color

    @State private var spinning = false

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline)
            .foregroundStyle(color)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

private static func iconName(for state: ScrapeItemState) -> String {
        switch state {
        case .pending: return "circle"                        // 待命
        case .running: return "arrow.triangle.2.circlepath"   // 进行中
        case .done: return "checkmark.circle.fill"            // 完成
        case .failed: return "xmark.circle.fill"              // 出错
        }
    }

    private static func iconColor(for state: ScrapeItemState) -> Color {
        switch state {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 外链：跳到 Safari 打开下厨房，用户在站里挑菜谱后复制链接回来抓
            Link(destination: Self.siteURL) {
                Label("去下厨房找菜谱", systemImage: "arrow.up.forward.square")
                    .font(.footnote)
            }

            TextEditor(text: $input)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    Text("每行一个菜谱 ID 或链接，例如 106125193")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .opacity(input.isEmpty ? 1 : 0)
                        .allowsHitTesting(false)
                }

            HStack {
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(hintColor)
                Spacer()
                Button("清空") { input = "" }
                    .font(.caption)
                    .disabled(input.isEmpty)
            }
        }
    }

    private var hintColor: Color {
        if ids.isEmpty { return Color(uiColor: .secondaryLabel) }
        return rawCount > maxBatch ? .orange : .green
    }

    private var hintText: String {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "最多 \(maxBatch) 个"
        }
        if ids.isEmpty { return "没有解析到有效的菜谱 ID" }
        if rawCount > maxBatch {
            return "识别到 \(rawCount) 个，本次只处理前 \(maxBatch) 个"
        }
        return "识别到 \(ids.count) 个菜谱"
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("下载封面图与步骤图到本地", isOn: $withImages)
            Toggle("强制更新已存在的菜谱", isOn: $forceUpdate)
            Text("图片会存进 App 沙盒，离线也能看；手机上建议一次抓几个到十几个。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scrape.total > 0 {
                let value = Double(scrape.current)
                let total = Double(max(1, scrape.total))
                ProgressView(value: value, total: total)
                HStack {
                    Text("第 \(scrape.current) / \(scrape.total) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((value / total) * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let title = scrape.currentTitle, !title.isEmpty {
                    Text("正在处理：\(title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // 系统不会为前台抓取保留后台运行时间，切走就停，得先说明白
            if scrape.isRunning {
                Label("切到后台 / 锁屏会暂停抓取，回到本页会自动继续。数量多时请保持 App 在前台。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            ForEach(Array(scrape.logs.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if scrape.logs.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if scrape.isRunning {
                Button(role: .destructive) { scrape.cancel() } label: {
                    Label("停止抓取", systemImage: "stop.circle")
                }
            }
        }
    }

    private var statusText: String {
        switch scrape.status {
        case .idle: return "还没有开始"
        case .running: return "抓取中…"
        case .waitingLogin: return "等待登录…"
        case .finished(let summary): return summary
        case .failed(let message): return message
        }
    }
}
