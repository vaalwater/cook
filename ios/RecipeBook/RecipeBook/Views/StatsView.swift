import SwiftUI
import UniformTypeIdentifiers

struct StatsView: View {
    @EnvironmentObject private var store: RecipeStore
    @EnvironmentObject private var scrape: ScrapeService

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDocument: RecipeBackupDocument?
    @State private var syncMessage: String?

    private var defaultFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "菜谱备份-\(formatter.string(from: Date())).json"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("本地数据") {
                    row("菜谱数量", "\(store.recipes.count) 道")
                    let images = store.localImageStats
                    row("图片数量", "\(images.count) 张")
                    row("图片体积", Format.bytes(images.bytes))
                    if let last = store.stats.lastCollected, !last.isEmpty {
                        row("最近抓取", Format.dateTime(last))
                    }
                    if let manifest = store.manifest, !manifest.exportedAt.isEmpty {
                        row("种子导出时间", Format.dateTime(manifest.exportedAt))
                    }
                }

                Section("抓取") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(scrape.sessionReady ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text("下厨房登录态")
                        Spacer()
                        Text(scrape.sessionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("清单") {
                    row("待做菜谱", "\(store.plan.count) 道")
                }

                Section {
                    Button {
                        backupDocument = RecipeBackupDocument(data: (try? store.backupData()) ?? Data())
                        showExporter = true
                    } label: {
                        Label("导出备份（菜谱 + 清单 + 删除记录）", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label("从备份恢复", systemImage: "square.and.arrow.down")
                    }

                    if let syncMessage {
                        Text(syncMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("备份存到「文件」App 或隔空投送出来后，在电脑上跑 npm run import:ios -- 备份.json 就能把手机上抓的新菜谱、删掉的菜谱、待做清单写回本地库。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("备份 / 同步")
                }

                Section("说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("无服务器，数据全部在手机里")
                            .font(.subheadline.weight(.semibold))
                        Text("菜谱存在 App 沙盒的 recipes.json，图片存在沙盒 images/ 目录，断网可用，不会上传到任何地方。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("新菜谱在「菜谱 → 右上角抓取」里粘贴下厨房链接抓取；App 自己抓页面、解析、存图，不经过服务器。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("已有的菜谱来自导出时的种子数据，之后电脑端 npm run export:ios 可以重新导出；App 里抓的新菜谱通过上面的备份导出 + npm run import:ios 回写电脑库。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if let message = store.errorMessage {
                    Section("异常") {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image("BrandMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: defaultFilename
            ) { result in
                switch result {
                case .success(let url):
                    syncMessage = "已导出：\(url.lastPathComponent)"
                case .failure(let error):
                    syncMessage = "导出失败：\(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        syncMessage = "没有读取该文件的权限"
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let report = try store.restore(from: data)
                        syncMessage = report.text
                    } catch {
                        syncMessage = "恢复失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    syncMessage = "选择文件失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

struct RecipeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
