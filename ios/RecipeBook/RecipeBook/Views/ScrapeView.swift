import SwiftUI

/// 手机上直接抓菜谱：粘贴下厨房菜谱 ID 或 URL（每行一个），App 自己抓页面、自己解析、自己存图。
struct ScrapeView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var scrape: ScrapeService

    @Environment(\.dismiss) private var dismiss

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
                Section { inputContent } header: { Text("菜谱 ID / 链接") }
                Section { optionsContent } header: { Text("选项") }
                Section { progressContent } header: { Text("进度") }
            }
            .navigationTitle("抓取菜谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scrape.start(
                            input: input,
                            options: ScrapeOptions(withImages: withImages, forceUpdate: forceUpdate)
                        )
                    } label: {
                        Label("开始", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(scrape.isRunning || ids.isEmpty)
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(startURL: Self.probeURL(first: ids.first)) { cookies in
                    scrape.finishLogin(cookies: cookies)
                }
            }
            .onChange(of: scrape.status) { _, status in
                if case .waitingLogin = status { showLogin = true }
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

    private var inputContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                ProgressView(value: Double(scrape.current), total: Double(max(1, scrape.total)))
                Text("第 \(scrape.current) / \(scrape.total) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
