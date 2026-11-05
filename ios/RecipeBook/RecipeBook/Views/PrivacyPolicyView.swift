import SwiftUI

/// App 内隐私政策页面（与 appstore/privacy-policy.html 内容保持一致）
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, body: String)] = [
        (
            "一句话结论",
            "本应用不要求注册、不采集任何个人身份信息、不接入第三方广告或统计分析 SDK。你收藏的菜谱与所有使用数据都只保存在你自己的设备上。「语音搜索」仅在你按住麦克风时临时拾音、经系统语音识别转成文字，不保存任何录音。"
        ),
        (
            "我们收集的信息",
            "我们不会收集任何个人信息，运行时不向服务器上报：姓名/手机号/邮箱等身份信息（应用无账号系统）；位置、通讯录、相册、相机（除你主动选择本地图片作为封面外，图片仅存本机）；麦克风录音（见下方「语音搜索与麦克风」）；使用行为、点击等分析数据；任何设备标识符（IDFA 等）。"
        ),
        (
            "语音搜索与麦克风",
            "「语音搜索」是可选功能：只有你按住搜索框右侧的麦克风按钮时才会拾音，松开即停止。拾取的音频仅用于调用系统语音识别（Apple Speech 框架）把你说的话转成文字填入搜索框；本应用不录制、不上传、不存储任何录音，音频不落盘、用完即弃。语音识别由 iOS 系统完成（可能在设备端或由 Apple 按其隐私政策处理），本应用接触不到原始音频的留存副本。不授权麦克风完全不影响其它功能，你也可以照常打字搜索；倒计时到点的语音播报在本机用系统语音合成生成，不涉及麦克风。"
        ),
        (
            "数据存储位置",
            "以下数据仅保存在你的 iPhone / iPad 本地（应用沙盒），不上传任何服务器：你收藏与抓取的菜谱；搜索历史（仅本机，可随时清空）；「待做清单」「下次做」标记与开干进度；你设置的步骤倒计时（仅用于本地通知）。卸载 App 后本地数据随沙盒一并删除。"
        ),
        (
            "网络使用说明",
            "「抓取菜谱」仅在你主动触发时，从公开第三方菜谱网站（如下厨房）获取公开内容，用于本机保存与浏览，不提交你的任何个人信息。「语音搜索」调用系统语音识别时，iOS 可能按 Apple 的策略在设备端或经由 Apple 服务完成识别，该过程由系统处理，本应用不提交你的任何身份信息、也不获取或存储识别用的音频。倒计时到点通过系统本地通知提醒，不依赖网络；到点语音播报由本机语音合成生成，同样不依赖网络。"
        ),
        (
            "信息分享与第三方",
            "我们不会将你的任何数据出售、出租或共享给第三方。应用不包含广告、不集成统计/广告 SDK、不嵌入第三方追踪脚本。"
        ),
        (
            "儿童隐私",
            "内容面向一般家庭烹饪用户，不含不当内容，亦不主动向儿童收集信息。如需删除本地数据，直接卸载 App 即可。"
        ),
        (
            "你的权利",
            "随时在 App 内「清空搜索历史」；随时删除单道菜谱或「清空待做清单」；卸载 App 以彻底删除全部本地数据。"
        ),
        (
            "政策变更",
            "如本政策变更，我们会在 App 内及官网更新并注明生效日期。"
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("《菜谱小本本》隐私政策")
                        .font(.title2.weight(.bold))
                    Text("最后更新：2026-11-05")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("© 2026 菜谱小本本")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
