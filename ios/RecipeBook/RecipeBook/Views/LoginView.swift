import SwiftUI
import WebKit

/// 登录下厨房：只有一个不可控制自动化行为的 WKWebView，让用户在里面扫码 / 输账号 / 拖滑块，
/// 完成后从这枚 WebView 的 Cookie 容器里取回 xiachufang.com 的 Cookie 交给抓取流程复用。
/// 登录这一步无法自动化，所以整个方案是「人工过一次验证 → 之后纯 HTTP 抓取」。
struct LoginView: View {
    let startURL: URL
    let onFinish: ([SiteCookie]) -> Void
    /// 取消时必须回调，用来唤醒 ScrapeService 里等待登录的 continuation
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var pageTitle = ""
    /// 用手势下滑关掉 sheet 时拿不到「取消」按钮的回调，靠这里兜底
    @State private var finished = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SiteLoginWebView(url: startURL, isLoading: $isLoading, pageTitle: $pageTitle)

                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在打开下厨房…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        // 必须先通知抓取流程，否则它会一直挂起在等待登录那一步
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") { collectCookies() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("登录成功后点右上角「完成登录」。遇到滑块验证就拖一下，站点会给这次会话下发凭证。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
            .onDisappear { if !finished { onCancel() } }
        }
    }

    private func collectCookies() {
        Task {
            let cookies = await Self.siteCookies()
            guard !cookies.isEmpty else {
                pageTitle = "没有读到 Cookie"
                return
            }
            SessionStore.save(cookies)
            finished = true
            onFinish(cookies)
            dismiss()
        }
    }

    static func siteCookies() async -> [SiteCookie] {
        let all = await withCheckedContinuation { (continuation: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        return SessionStore.filterSiteCookies(
            all.filter { $0.domain.localizedCaseInsensitiveContains("xiachufang.com") }
                .map { SiteCookie(name: $0.name, value: $0.value, domain: $0.domain) }
        )
    }
}

struct SiteLoginWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var pageTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        // 桌面 UA：站点对移动端 WebView 更敏感
        view.customUserAgent = SiteClient.userAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: SiteLoginWebView

        init(parent: SiteLoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.pageTitle = error.localizedDescription
        }
    }
}
