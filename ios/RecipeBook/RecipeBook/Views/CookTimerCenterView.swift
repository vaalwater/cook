import SwiftUI
import UIKit

/// 顶部倒计时入口：没有倒计时时是普通时钟图标，有倒计时时变成「绿底 + 中间个数」的徽标（有已到点的转红）
struct TimerToolbarLabel: View {
    let count: Int
    let hasFired: Bool
    /// 为空时跟图标一起显示的文字（开干页用「计时」，首页不要）
    var emptyTitle: String? = nil

    var body: some View {
        Group {
            if count > 0 {
                ZStack {
                    Circle()
                        .fill(hasFired ? Color.red : Color.green)
                        .frame(width: 26, height: 26)
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 28, minHeight: 28)
            } else if let emptyTitle {
                Label(emptyTitle, systemImage: "timer")
            } else {
                Image(systemName: "timer")
            }
        }
    }
}

/// 倒计时总览：进度条 + ±N 分钟快捷调整 + 暂停 / 删除。开干页顶部入口与菜谱首页入口共用这一个页面。
struct CookTimerCenterView: View {
    @EnvironmentObject private var timers: CookTimerManager
    @Environment(\.dismiss) private var dismiss

    /// 跳转系统闹钟失败（URL scheme 不被识别）时，弹出提示引导用户手动添加
    @State private var showAlarmHint = false

    /// 点标题回调（recipeId + stepIndex）。从开干页进来时传，用来关掉弹窗并聚焦到对应步骤卡片；
    /// 从别处进来传 nil，标题就是普通文字。
    var onFocusStep: ((Int, Int) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Group {
                if timers.notificationAuthorized == false {
                    notificationHint
                }
                if timers.timers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("还没有倒计时")
                            .font(.headline)
                        Text("在开干模式的开工顺序卡片上点「计时」即可添加。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    List {
                        ForEach(timers.timers) { timer in
                            timerRow(timer)
                                // 删除放在左滑里，避免和暂停贴在一起误触
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        timers.delete(id: timer.id)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("倒计时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                // 系统闹钟入口：放在标题右侧（弹层右上角），跳到 时钟 App 闹钟页，让用户手动建
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openClockAlarm()
                    } label: {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .alert("请手动添加系统闹钟", isPresented: $showAlarmHint) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("当前系统暂不支持直接跳转，请在「时钟」App 里手动添加闹钟。")
            }
        }
    }

    /// 通知被拒时提示：锁屏后到点不会响铃，引导去系统设置开启
    private var notificationHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("锁屏后计时结束不会响铃")
                    .font(.subheadline.weight(.semibold))
                Text("后台提醒依赖通知权限，去设置开启即可。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("去设置").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(12)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 4)
    }

    private func timerRow(_ timer: CookTimer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: timer.fired ? "bell.badge.fill" : (timer.isRunning ? "timer" : "pause.circle"))
                    .foregroundStyle(timer.fired ? .red : (timer.isRunning ? .orange : .secondary))

                // 带步骤信息的倒计时：点标题回到开干页并聚焦到那一步
                if let focus = onFocusStep, let recipeId = timer.recipeId, let stepIndex = timer.stepIndex {
                    Button {
                        focus(recipeId, stepIndex)
                    } label: {
                        HStack(spacing: 3) {
                            Text(timer.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Image(systemName: "arrow.right.circle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(timer.title)
                        .font(.subheadline.weight(.medium))
                }

                Spacer(minLength: 8)
                Text(timer.fired ? "已到点" : timer.remainingText)
                    .font(.system(.subheadline, design: .default).monospacedDigit().weight(.semibold))
                    .foregroundStyle(timer.fired ? .red : .primary)
            }

            ProgressView(value: timer.progress)
                .tint(timer.fired ? .red : .orange)

            // 排布：-5 -3 -1 | 暂停 | +1 +3 +5；删除改左滑，避免手滑误删
            HStack(spacing: 8) {
                ForEach([-5, -3, -1], id: \.self) { delta in
                    adjustButton(timer, delta)
                }

                iconButton(
                    timer.isRunning ? "pause.fill" : "play.fill",
                    tint: timer.isRunning ? .orange : .green,
                    disabled: timer.fired
                ) {
                    timers.toggle(id: timer.id)
                }

                ForEach([1, 3, 5], id: \.self) { delta in
                    adjustButton(timer, delta)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// 跳到系统「时钟」App 的闹钟页（只是入口）。无法在代码里直接建系统闹钟，只能让用户去手动加。
    private func openClockAlarm() {
        let url = URL(string: "clock-alarm://")!
        UIApplication.shared.open(url) { success in
            if !success { showAlarmHint = true }
        }
    }

    /// ±N 分钟（调整的是总时长 = 剩余时长）
    private func adjustButton(_ timer: CookTimer, _ delta: Int) -> some View {
        Button {
            timers.adjustMinutes(id: timer.id, by: Double(delta))
        } label: {
            Text(delta > 0 ? "+\(delta)" : "\(delta)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(delta > 0 ? .orange : .primary)
                .frame(minWidth: 42, minHeight: 34)
                .background(
                    Capsule().fill(delta > 0 ? Color.orange.opacity(0.18) : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }

    /// 只留图标的暂停 / 继续按钮
    private func iconButton(_ symbol: String, tint: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : tint)
                .frame(minWidth: 44, minHeight: 34)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// 开工顺序卡片上点「计时」弹出的设置窗：标题 = 步骤缩写（多道菜时带菜名），默认值 = 预计时间的中间值
struct CookTimerSetupView: View {
    let draft: TimerDraft

    @EnvironmentObject private var timers: CookTimerManager
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Double

    init(draft: TimerDraft) {
        self.draft = draft
        _minutes = State(initialValue: max(1, round(draft.suggestedMinutes)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("倒计时标题") {
                    Text(draft.title)
                        .font(.subheadline)
                }

                Section("时长（分钟）") {
                    HStack {
                        Text("\(Int(minutes)) 分钟")
                            .font(.system(.title3, design: .default).monospacedDigit().weight(.semibold))
                            .frame(minWidth: 92, alignment: .leading)
                        Spacer()
                        Stepper("", value: $minutes, in: 1...600, step: 1)
                            .labelsHidden()
                    }

                    // ±N 分钟快捷调整（±1 由上面的 Stepper 负责，这里不再重复）
                    HStack(spacing: 8) {
                        ForEach([-10, -5, -3, 3, 5, 10], id: \.self) { delta in
                            Button {
                                minutes = max(1, minutes + Double(delta))
                            } label: {
                                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                    .font(.footnote.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(delta > 0 ? .orange : .primary)
                                    .frame(minWidth: 42, minHeight: 36)
                                    .background(
                                        Capsule().fill(delta > 0 ? Color.orange.opacity(0.18) : Color(.tertiarySystemFill))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("默认值取该步骤预计时间的中间值，可用上面的 ± 快捷调整。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        timers.add(
                            title: draft.title,
                            recipeId: draft.recipeId,
                            stepIndex: draft.stepIndex,
                            minutes: minutes
                        )
                        dismiss()
                    } label: {
                        Label("开始倒计时", systemImage: "timer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .navigationTitle("设置倒计时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
