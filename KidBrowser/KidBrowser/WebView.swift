import SwiftUI
import WebKit

/// 嚴格白名單 WebView。
///
/// 規則（對應你選的「完全只開指定網址」）：
///   1. 主框架（main frame）導航：只有 sites.json 裡列出的「確切網址」才放行，
///      其餘一律 .cancel —— 小孩點到頁面內任何外連都跳不出去。
///   2. 子框架 / 子資源（iframe、圖片、影片、CSS、JS）：放行，
///      否則嵌入的 YouTube、圖片、影片會無法載入。
struct WebView: UIViewRepresentable {
    let url: URL
    let store: SiteStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 影片可以內嵌播放、且不需先點一下才播（小孩友善）
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false  // 不讓滑動上一頁/下一頁
        webView.scrollView.bounces = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 若要顯示的網址換了，重新載入
        if webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let store: SiteStore
        init(store: SiteStore) { self.store = store }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

            // 子框架 / 子資源（影片、iframe、圖片…）一律放行
            if let target = navigationAction.targetFrame, !target.isMainFrame {
                decisionHandler(.allow); return
            }

            // 主框架：只有白名單裡的確切網址才放行
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            if store.isAllowed(url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)   // 擋掉所有沒列在 sites.json 的網址
            }
        }
    }
}
