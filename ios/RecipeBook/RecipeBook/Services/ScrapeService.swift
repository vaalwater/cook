import Foundation
import SwiftUI

enum ScrapeStatus: Equatable {
    case idle
    case running
    case waitingLogin
    case finished(summary: String)
    case failed(message: String)
}

struct ScrapeOptions {
    var withImages: Bool = true
    var forceUpdate: Bool = false
    var imageSize: Int = 1000
    var maxBatch: Int = 20
}

/// 手机上的抓取流程：探测会话 → 必要时请人工登录/过滑块 → 逐个抓页面 → 解析 → 图片本地化 → 写入本地库。
@MainActor
final class ScrapeService: ObservableObject {
    let store: RecipeStore

    @Published var status: ScrapeStatus = .idle
    @Published var logs: [String] = []
    @Published var current: Int = 0
    @Published var total: Int = 0
    /// 当前正在处理第几道菜（给进度条用）
    @Published var currentTitle: String?
    @Published var sessionReady: Bool = false
    @Published var sessionMessage: String = "未检查登录态"

    private var client: SiteClient?
    private var parser: RecipeParser?
    private var task: Task<Void, Never>?
    private var loginContinuation: CheckedContinuation<[SiteCookie], Never>?

    init(store: RecipeStore) {
        self.store = store
    }

    // MARK: - 输入解析

    /// 支持纯 ID、完整 URL、短链，用换行/逗号/空格分隔，去重保序
    static func parseIDs(_ input: String) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for token in input.replacingOccurrences(of: "\r", with: "").split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let raw = String(token).trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let id: String
            if let range = raw.range(of: "/recipe/(\\d+)", options: .regularExpression) {
                id = String(raw[range]).replacingOccurrences(of: "/recipe/", with: "")
            } else {
                id = raw
            }
            guard id.allSatisfy({ $0.isNumber }), !seen.contains(id) else { continue }
            seen.insert(id)
            ids.append(id)
        }
        return ids
    }

    // MARK: - 流程

    var isRunning: Bool {
        if case .running = status { return true }
        if case .waitingLogin = status { return true }
        return false
    }

    func start(input: String, options: ScrapeOptions) {
        guard !isRunning else { return }
        let ids = Array(Self.parseIDs(input).prefix(options.maxBatch))
        guard !ids.isEmpty else {
            status = .failed(message: "没有解析到菜谱 ID")
            return
        }
        task = Task { await run(ids: ids, options: options) }
    }

    func cancel() {
        // 正在等人工登录时，光 cancel Task 不会唤醒 CheckedContinuation
        if case .waitingLogin = status { resumeLogin(with: []) }
        task?.cancel()
        task = nil
        status = .failed(message: "已取消")
        log("已取消")
    }

    /// LoginView 完成登录后调用
    func finishLogin(cookies: [SiteCookie]) {
        resumeLogin(with: cookies)
    }

    /// LoginView 点了「取消」时必须调用，否则等登录的 Task 永远挂起，
    /// 状态卡死在 .waitingLogin，之后再也 start 不了（历史 bug）。
    /// 这里回一份空 Cookie，`run()` 收到空数组即认定用户放弃。
    func cancelLogin() {
        resumeLogin(with: [])
    }

    private func resumeLogin(with cookies: [SiteCookie]) {
        let continuation = loginContinuation
        loginContinuation = nil
        continuation?.resume(returning: cookies)
    }

    func checkSession() async {
        let client = SiteClient(cookies: SessionStore.load()?.cookies ?? [])
        self.client = client
        let result = await client.probe(String(format: SessionStore.recipeURLTemplate, "106125193"))
        switch result {
        case .success:
            sessionReady = true
            sessionMessage = "登录态有效"
        case .failure(let error):
            sessionReady = false
            sessionMessage = error.message
        }
        SessionStore.save(client.exportCookies())
    }

    private func log(_ message: String) {
        logs.append(message)
    }

    /// App 退到后台：iOS 会挂起进程、网络请求停住。这里不做后台任务，
    /// 只在日志里说明现状，避免用户误以为卡死。
    func noteBackgrounded() {
        guard isRunning else { return }
        let text = "已切到后台，抓取暂停；回到前台会自动继续。"
        guard logs.last != text else { return }
        log(text)
    }

    private func run(ids: [String], options: ScrapeOptions) async {
        status = .running
        current = 0
        total = ids.count
        currentTitle = nil
        logs = []

        let client = SiteClient(cookies: SessionStore.load()?.cookies ?? [])
        self.client = client
        log("目标 \(ids.count) 个菜谱，最多同时在一次任务里处理 \(options.maxBatch) 个")

        let probeUrl = String(format: SessionStore.recipeURLTemplate, ids[0])
        var sessionOK = false
        for attempt in 0..<2 {
            let probe = await client.probe(probeUrl)
            if case .success = probe {
                sessionOK = true
                if attempt == 0 { log("登录态有效，开始抓取。") } else { log("会话已恢复，继续抓取。") }
                break
            }
            guard case .failure(let error) = probe else { break }
            log("无法访问菜谱页：\(error.message)")
            SessionStore.save(client.exportCookies())

            if error.code == .challenge {
                log("下厨房要求人机校验，请在弹出的网页里拖一下滑块。")
            } else if error.code == .notFound {
                log("这个菜谱如果确认存在，那多半是人机校验在伪装成 404。")
            }

            let cookies = await waitForLogin()
            // 用户点了「取消」→ 空 Cookie，直接中止，不要再回到 probe 循环死等
            guard !cookies.isEmpty else {
                status = .failed(message: "已取消登录，抓取中止")
                log("已取消登录")
                return
            }
            client.setCookies(cookies)
            SessionStore.save(cookies)
        }

        guard sessionOK else {
            status = .failed(message: "登录后仍无法访问菜谱页，建议稍后再试")
            return
        }
        SessionStore.save(client.exportCookies())
        sessionReady = true
        sessionMessage = "登录态有效"

        do {
            parser = try await RecipeParser.create()
        } catch {
            status = .failed(message: error.localizedDescription)
            return
        }

        var added = 0
        var updated = 0
        var skipped = 0
        var failed = 0
        var imageCount = 0

        for (index, id) in ids.enumerated() {
            if Task.isCancelled { break }
            current = index + 1
            currentTitle = nil
            let url = String(format: SessionStore.recipeURLTemplate, id)

            if !options.forceUpdate, store.hasRecipe(id: Int(id) ?? 0) {
                skipped += 1
                log("(\(index + 1)/\(ids.count)) 跳过 \(id)（已存在）")
                continue
            }

            do {
                let page = try await client.fetchHtml(url)
                guard let parser else { break }
                let raw = try await parser.extractRecipe(html: page.html, pageUrl: page.finalUrl)
                guard let recipeId = Int(id) else { continue }

                var recipe = normalize(raw: raw, id: recipeId, url: url)
                guard !recipe.title.isEmpty else {
                    throw ScrapeError(code: .parseFailed, message: "未能解析出菜谱名称")
                }
                currentTitle = recipe.title

                if options.withImages {
                    let cover = await ImageDownloader.download(
                        recipe.coverImage,
                        to: store.imageDir,
                        dirName: "covers",
                        name: id,
                        size: options.imageSize
                    )
                    if cover.ok {
                        recipe.coverImage = cover.publicPath
                        if !cover.skipped { imageCount += 1 }
                    } else {
                        log("  封面图下载失败：\(cover.error ?? "")")
                    }

                    for stepIndex in recipe.steps.indices {
                        guard !recipe.steps[stepIndex].image.isEmpty else { continue }
                        let result = await ImageDownloader.download(
                            recipe.steps[stepIndex].image,
                            to: store.imageDir,
                            dirName: "steps",
                            name: "\(id)-\(recipe.steps[stepIndex].index)",
                            size: options.imageSize
                        )
                        if result.ok {
                            recipe.steps[stepIndex].image = result.publicPath
                            if !result.skipped { imageCount += 1 }
                        }
                    }
                }

                let outcome = store.upsert(recipe)
                if outcome.isNew { added += 1 } else { updated += 1 }
                log("(\(index + 1)/\(ids.count)) ✓ \(recipe.title)")
                if let warnings = raw.warnings, !warnings.isEmpty {
                    log("  提示：\(warnings.joined(separator: "、"))")
                }
            } catch {
                failed += 1
                log("(\(index + 1)/\(ids.count)) ✗ \(id)：\(error.localizedDescription)")
                let code = (error as? ScrapeError)?.code
                if code == .challenge || code == .loginRequired {
                    status = .failed(message: "会话失效，请重新登录后重试")
                    return
                }
            }
        }

        currentTitle = nil
        let summary = "新抓 \(added) 条，更新 \(updated) 条，跳过 \(skipped) 条，失败 \(failed) 条，图片 \(imageCount) 张"
        log(summary)
        status = .finished(summary: summary)
    }

    private func waitForLogin() async -> [SiteCookie] {
        status = .waitingLogin
        return await withCheckedContinuation { (continuation: CheckedContinuation<[SiteCookie], Never>) in
            loginContinuation = continuation
        }
    }

    /// RawRecipe → Recipe 的字段规整（过滤空项、补齐 index，保持既有规则不变）
    private func normalize(raw: RawRecipe, id: Int, url: String) -> Recipe {
        let now = ISOStamp.string(from: Date())
        let ingredients = (raw.ingredients ?? [])
            .filter { ($0.name ?? "").isEmpty == false }
            .map { IngredientItem(name: $0.name ?? "", amount: $0.amount ?? "") }
        let steps = (raw.steps ?? [])
            .enumerated()
            .filter { !($0.element.text ?? "").isEmpty || !($0.element.image ?? "").isEmpty }
            .map { index, step in
                RecipeStep(index: step.index ?? index + 1, text: step.text ?? "", image: step.image ?? "")
            }
        return Recipe(
            id: id,
            url: raw.url ?? url,
            title: raw.title ?? "",
            description: raw.description ?? "",
            coverImage: raw.coverImage ?? "",
            author: raw.author ?? "",
            servings: raw.servings ?? "",
            ingredients: ingredients,
            ingredientGroups: IngredientClassifier.classify(ingredients),
            steps: steps,
            tips: raw.tips ?? "",
            tags: raw.tags ?? [],
            madeCount: raw.madeCount ?? "",
            favCount: raw.favCount ?? "",
            sourceUrl: url,
            collectedAt: now,
            updatedAt: now
        )
    }
}
