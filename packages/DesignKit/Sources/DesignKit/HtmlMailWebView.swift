import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// HTML 邮件沙箱渲染（JOURNEY-004，规范 §7）：
/// CSP `default-src 'none'; style-src 'unsafe-inline'; img-src data:` ——远程图片默认禁（隐私+防追踪），
/// 仅内联样式与内嵌 data 图生效；用户"显示远程图片"开关后续迭代接入。
struct HtmlMailWebView: View {
    let html: String

    var body: some View {
        #if canImport(WebKit)
        MailWebViewRepresentable(sandboxedHTML: Self.sandboxed(html))
            #if os(macOS)
            .background(Color.white)
            #else
            .background(Color.white)
            #endif
        #else
        Text(html)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(DesignTokens.inkMuted)
            .padding()
        #endif
    }

    /// 注入 CSP 与基础排版（邮件 HTML 常缺 body 样式，兜底字体与边距）。
    static func sandboxed(_ html: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; style-src 'unsafe-inline'; img-src data:;">
        <style>
          body { font: -apple-system 14px; color: #2a3444; margin: 0; padding: 4px 0;
                 word-break: break-word; line-height: 1.7; }
          table { max-width: 100%; }
          img { max-width: 100%; height: auto; }
          a { color: #006FCF; }
        </style></head><body>\(html)</body></html>
        """
    }
}

#if canImport(WebKit)
#if os(macOS)
struct MailWebViewRepresentable: NSViewRepresentable {
    let sandboxedHTML: String

    func makeNSView(context: Context) -> WKWebView {
        configure(WKWebView())
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(sandboxedHTML, baseURL: nil)
    }
}
#else
struct MailWebViewRepresentable: UIViewRepresentable {
    let sandboxedHTML: String

    func makeUIView(context: Context) -> WKWebView {
        configure(WKWebView())
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(sandboxedHTML, baseURL: nil)
    }
}
#endif

private func configure(_ webView: WKWebView) -> WKWebView {
    // 沙箱加固：禁 JS 与链接预览（点击链接后续迭代经安全审查后放行）
    webView.configuration.preferences.javaScriptEnabled = false
    webView.allowsLinkPreview = false
    #if os(iOS)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.showsVerticalScrollIndicator = true
    #endif
    return webView
}
#endif
