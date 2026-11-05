import Foundation
import AVFoundation
import AudioToolbox
import UserNotifications

/**
 * 开干模式里的步骤倒计时。
 *
 * 设计要点：
 *   - 一条倒计时对应「某道菜的某个步骤」，开工顺序里点「完成」会按 recipeId + stepIndex 一起删掉
 *   - 计时靠 endsAt 绝对时间算，App 被杀掉再回来也能算出正确剩余时间（不会因为挂起而变慢）
 *   - 只有 app 在前台才能响铃 + 语音；同时发一条本地通知，切后台也能收到
 *   - 全部写 timers.json，重启后还在
 */
struct CookTimer: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var recipeId: Int?
    var stepIndex: Int?
    var totalSeconds: Double
    var remainingSeconds: Double
    var endsAt: Date?      // 运行中才有值
    var isRunning: Bool
    var fired: Bool

    init(id: String = UUID().uuidString,
         title: String,
         recipeId: Int? = nil,
         stepIndex: Int? = nil,
         totalSeconds: Double,
         remainingSeconds: Double,
         endsAt: Date? = nil,
         isRunning: Bool = false,
         fired: Bool = false) {
        self.id = id
        self.title = title
        self.recipeId = recipeId
        self.stepIndex = stepIndex
        self.totalSeconds = totalSeconds
        self.remainingSeconds = remainingSeconds
        self.endsAt = endsAt
        self.isRunning = isRunning
        self.fired = fired
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, 1 - remainingSeconds / totalSeconds))
    }

    var remainingText: String {
        let t = max(0, Int(ceil(remainingSeconds)))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var remainingMinutes: Double { remainingSeconds / 60.0 }
}

/// 开工顺序卡片上点「计时」时，临时保存的草稿（决定弹窗内容）
struct TimerDraft: Identifiable {
    let id = UUID()
    let title: String
    let recipeId: Int?
    let stepIndex: Int?
    let suggestedMinutes: Double
}

/// 倒计时管理器。所有方法与 1s 心跳都跑在主线程。
final class CookTimerManager: NSObject, ObservableObject {
    @Published private(set) var timers: [CookTimer] = []
    /// 刚刚到点的那条，UI 拿到后弹提示
    @Published var lastFired: CookTimer?
    /// 通知授权状态：nil = 还不知道，true = 已授权，false = 被拒绝（锁屏后到点不会响铃）
    @Published var notificationAuthorized: Bool? = nil

    private var ticker: Timer?
    private let synth = AVSpeechSynthesizer()

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RecipeBook/timers.json")
    }

    override init() {
        super.init()
        load()
        reconcileAfterLaunch()
        refreshNotificationAuthorization()
        synth.delegate = self
    }

    // MARK: - 增删改

    func add(title: String, recipeId: Int?, stepIndex: Int?, minutes: Double) {
        let total = max(60, round(minutes) * 60)
        let timer = CookTimer(
            title: title,
            recipeId: recipeId,
            stepIndex: stepIndex,
            totalSeconds: total,
            remainingSeconds: total
        )
        timers.insert(timer, at: 0)
        // 权限申请放到第一次真正建倒计时时，别在 App 冷启动就弹窗打扰
        requestNotificationPermissionIfNeeded()
        start(id: timer.id)
    }

    func start(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].remainingSeconds = max(1, timers[index].remainingSeconds)
        timers[index].endsAt = Date().addingTimeInterval(timers[index].remainingSeconds)
        timers[index].isRunning = true
        timers[index].fired = false
        startTicker()
        // 交给系统排一条到点通知：App 被挂起 / 杀掉也能响，这是后台唯一可靠的手段
        scheduleNotification(timers[index])
        save()
    }

    func pause(id: String) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        if let end = timers[index].endsAt {
            timers[index].remainingSeconds = max(0, end.timeIntervalSinceNow)
        }
        timers[index].endsAt = nil
        timers[index].isRunning = false
        cancelNotification(id: id)
        save()
        stopTickerIfIdle()
    }

    func toggle(id: String) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timer.isRunning ? pause(id: id) : start(id: id)
    }

    func delete(id: String) {
        cancelNotification(id: id)
        timers.removeAll { $0.id == id }
        save()
        stopTickerIfIdle()
    }

    /// 某道菜（或几道菜）不再做了：它的步骤倒计时全部清掉，到点通知一并撤销
    func delete(recipeIds: [Int]) {
        let ids = Set(recipeIds)
        guard !ids.isEmpty else { return }
        let before = timers.count
        timers.filter { $0.recipeId.map(ids.contains) ?? false }.forEach { cancelNotification(id: $0.id) }
        timers.removeAll { $0.recipeId.map(ids.contains) ?? false }
        guard timers.count != before else { return }
        save()
        stopTickerIfIdle()
    }

    /// 开工顺序里点「完成」：把这一条步骤对应的倒计时一起删掉
    func delete(recipeId: Int, stepIndex: Int) {
        let before = timers.count
        let removed = timers.filter { $0.recipeId == recipeId && $0.stepIndex == stepIndex }
        timers.removeAll { $0.recipeId == recipeId && $0.stepIndex == stepIndex }
        guard timers.count != before else { return }
        removed.forEach { cancelNotification(id: $0.id) }
        save()
        stopTickerIfIdle()
    }

    func deleteAllFired() {
        timers.filter { $0.fired }.forEach { cancelNotification(id: $0.id) }
        timers.removeAll { $0.fired }
        save()
        stopTickerIfIdle()
    }

    /// 列表里拖动修改：改的是「还剩多少分钟」，总时长不够就一起放大
    func setRemainingMinutes(id: String, minutes: Double) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let seconds = max(60, round(minutes) * 60)
        timers[index].remainingSeconds = seconds
        timers[index].totalSeconds = max(timers[index].totalSeconds, seconds)
        timers[index].fired = false
        if timers[index].isRunning {
            timers[index].endsAt = Date().addingTimeInterval(seconds)
            startTicker()
            scheduleNotification(timers[index])
        }
        save()
    }

    /// ±N 分钟快捷调整：改的就是总时长 = 剩余时长（调完按新时长重新跑，进度条同步归零重新走）
    func adjustMinutes(id: String, by deltaMinutes: Double) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let minutes = max(1, Int(round(timers[index].remainingMinutes)) + Int(deltaMinutes))
        let seconds = Double(minutes * 60)
        timers[index].totalSeconds = seconds
        timers[index].remainingSeconds = seconds
        timers[index].fired = false
        if timers[index].isRunning {
            timers[index].endsAt = Date().addingTimeInterval(seconds)
            startTicker()
            scheduleNotification(timers[index])
        }
        save()
    }

    func timer(forRecipeId recipeId: Int, stepIndex: Int) -> CookTimer? {
        timers.first { $0.recipeId == recipeId && $0.stepIndex == stepIndex }
    }

    var runningCount: Int { timers.filter { $0.isRunning }.count }

    // MARK: - 心跳

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTickerIfIdle() {
        guard !timers.contains(where: { $0.isRunning }) else { return }
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        var needsSave = false
        for index in timers.indices where timers[index].isRunning {
            guard let end = timers[index].endsAt else { continue }
            let left = end.timeIntervalSinceNow
            if left <= 0 {
                timers[index].remainingSeconds = 0
                timers[index].endsAt = nil
                timers[index].isRunning = false
                timers[index].fired = true
                cancelNotification(id: timers[index].id)
                fire(timers[index])
                needsSave = true
            } else {
                timers[index].remainingSeconds = left
            }
        }
        if needsSave { save() }
        stopTickerIfIdle()
        // App 被杀后重启：给仍在跑的计时重新排「到点通知」，否则锁屏 / 后台时到点不会响铃
        for index in timers.indices where timers[index].isRunning {
            if let end = timers[index].endsAt, end.timeIntervalSinceNow > 0 {
                scheduleNotification(timers[index])
            }
        }
    }

    /// App 被杀掉期间到点的：静默标记，不再补响铃，避免回来时一堆乱响
    private func reconcileAfterLaunch() {
        var needsSave = false
        for index in timers.indices where timers[index].isRunning {
            guard let end = timers[index].endsAt else { continue }
            let left = end.timeIntervalSinceNow
            if left <= 0 {
                timers[index].remainingSeconds = 0
                timers[index].endsAt = nil
                timers[index].isRunning = false
                timers[index].fired = true
                needsSave = true
            } else {
                timers[index].remainingSeconds = left
            }
        }
        if needsSave { save() }
        if timers.contains(where: { $0.isRunning }) { startTicker() }
    }

    // MARK: - 提醒

    private func fire(_ timer: CookTimer) {
        lastFired = timer
        AudioServicesPlaySystemSound(1005)                        // 短信音
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        // 朗读前把音频会话切到 playback：走媒体音量（而非铃声音量）、默认外放，
        // 避免停留在语音搜索遗留的 playAndRecord 而路由到听筒导致播报音量偏小；
        // duckOthers 让播报期间压低其它音频，结束后由 delegate 释放会话恢复。
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // 配置失败也不阻塞播报，按默认会话播
        }
        let utterance = AVSpeechUtterance(string: "计时结束，\(timer.title)")
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synth.speak(utterance)
        notify(timer)
    }

    /// 立即弹一条（App 在前台、计时器自己走到点时用）
    private func notify(_ timer: CookTimer) {
        let content = UNMutableNotificationContent()
        content.title = "⏰ 计时结束"
        content.body = timer.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: timer.id + "-fired", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 预先排一条到点通知（iOS 没有开放「写系统闹钟」的 API，这是唯一后台也生效的办法）。
    /// 首次排期会顺带申请通知权限，用户点允许后这条也能生效。
    private func scheduleNotification(_ timer: CookTimer) {
        guard let end = timer.endsAt else { return }
        let center = UNUserNotificationCenter.current()
        let addRequest = {
            let interval = max(1, end.timeIntervalSinceNow)
            let content = UNMutableNotificationContent()
            content.title = "⏰ 计时结束"
            content.body = timer.title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(
                UNNotificationRequest(identifier: timer.id, content: content, trigger: trigger),
                withCompletionHandler: nil
            )
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                addRequest()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { addRequest() }
                }
            default:
                break
            }
        }
    }

    private func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// 读取当前通知授权状态，供 UI 判断要不要提示用户去开权限（否则锁屏后到点不响铃）
    func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted: Bool? = {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: return true
                case .denied: return false
                case .notDetermined: return nil
                @unknown default: return nil
                }
            }()
            DispatchQueue.main.async { self.notificationAuthorized = granted }
        }
    }

    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                self.refreshNotificationAuthorization()
            }
        }
    }

    // MARK: - 持久化

    private func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(timers) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load() {
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CookTimer].self, from: data) else { return }
        timers = list
    }
}

// MARK: - 语音播报会话回收

extension CookTimerManager: AVSpeechSynthesizerDelegate {
    /// 播报结束后释放 playback 会话，让被 duck 的其它音频恢复，并避免长期占用音频路由。
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
