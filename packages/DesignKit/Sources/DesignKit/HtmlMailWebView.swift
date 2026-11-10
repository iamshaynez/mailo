import Foundation
import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// HTML 邮件沙箱渲染（JOURNEY-004/014/016 · DESIGN-006 · PERF-005）。
/// 相同文档由 coordinator 抑制重载；主题只经 CSS media query 响应。
struct HtmlMailWebView: View, Equatable {
    let html: String
    var allowRemoteImages: Bool = false
    var viewportHeight: CGFloat?
    var viewportWidth: CGFloat?

    var body: some View {
        #if canImport(WebKit)
        MailWebViewRepresentable(sandboxedHTML: Self.sandboxed(html, allowRemoteImages: allowRemoteImages),
                                 viewportHeight: viewportHeight, viewportWidth: viewportWidth)
            .background(ReaderSurface())
        #else
        Text(html)
            .font(DesignTokens.Typo.body.monospaced())
            .foregroundColor(DesignTokens.inkMuted)
            .padding()
        #endif
    }

    /// 将 HTML ideal size 限制在 reader 提供的实际正文视口内（JOURNEY-014）。
    static func constrainedSize(proposedWidth: CGFloat?, proposedHeight: CGFloat?,
                                viewportHeight: CGFloat?, viewportWidth: CGFloat? = nil) -> CGSize {
        let maxBodyHeight = max(160, viewportHeight ?? 820)
        let rawWidth = proposedWidth ?? 0
        let width = viewportWidth.map { max(0, $0) }
            ?? (rawWidth.isFinite && rawWidth > 0 ? rawWidth : DesignTokens.readingMeasure)
        let height = proposedHeight.flatMap { $0 > 0 ? min(maxBodyHeight, $0) : nil } ?? maxBodyHeight
        return CGSize(width: max(0, width), height: min(maxBodyHeight, height))
    }

    /// 注入 CSP 与共享阅读色标；作者显式样式不反转。
    static func sandboxed(_ html: String, allowRemoteImages: Bool = false) -> String {
        let imgPolicy = allowRemoteImages ? "img-src data: https:" : "img-src data:"
        let source = html.lowercased()
        let hasAuthorPresentation = ["<style", "style=", "class=", "bgcolor="]
            .contains { source.contains($0) }
        let bodyClass = hasAuthorPresentation ? " class=\"mailo-authored\"" : ""
        let lightTop = cssHex(.readerBodyTop, .light)
        let darkTop = cssHex(.readerBodyTop, .dark)
        let darkBottom = cssHex(.readerBodyBottom, .dark)
        let lightLink = cssHex(.brandBlue, .light)
        let darkLink = cssHex(.brandBlueDeep, .dark)
        let lightInk = cssHex(.inkBody, .light)
        let darkInk = cssHex(.inkBody, .dark)

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; style-src 'unsafe-inline'; \(imgPolicy);">
        <style>
          :root { color-scheme: light dark; }
          html { background: \(lightTop); }
          body { font: -apple-system 14px; color: \(lightInk); background: #FFFFFF;
                 box-sizing: border-box; max-width: 600px; min-height: 100vh;
                 margin: 0 auto; padding: 16px 0; word-break: break-word; line-height: 1.65; }
          body:not(.mailo-authored) { background: \(lightTop); }
          table { max-width: 100%; }
          img { max-width: 100%; height: auto; }
          ::-webkit-scrollbar { width: 0; height: 0; }
          a { color: \(lightLink); }
          @media (prefers-color-scheme: dark) {
            html { background: \(darkBottom); }
            body:not(.mailo-authored) { color: \(darkInk); background: \(darkTop); }
            body:not(.mailo-authored) a { color: \(darkLink); }
          }
        </style></head><body\(bodyClass)>\(html)</body></html>
        """
    }

    private static func cssHex(_ role: DesignTokens.ThemeRole, _ scheme: ColorScheme) -> String {
        String(format: "#%06X", DesignTokens.hex(role, for: scheme))
    }
}

#if canImport(WebKit)
#if os(macOS)
struct MailWebViewRepresentable: NSViewRepresentable {
    let sandboxedHTML: String
    let viewportHeight: CGFloat?
    let viewportWidth: CGFloat?

    func makeCoordinator() -> MailWebViewLoadGuard { MailWebViewLoadGuard() }

    func makeNSView(context: Context) -> WKWebView {
        configure(WKWebView())
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.shouldLoad(sandboxedHTML) else { return }
        webView.loadHTMLString(sandboxedHTML, baseURL: nil)
    }

    /// HTML 内容不参与父布局；只使用 reader 传入的视口（JOURNEY-014）。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        HtmlMailWebView.constrainedSize(proposedWidth: proposal.width, proposedHeight: proposal.height,
                                        viewportHeight: viewportHeight, viewportWidth: viewportWidth)
    }
}
#else
struct MailWebViewRepresentable: UIViewRepresentable {
    let sandboxedHTML: String
    let viewportHeight: CGFloat?
    let viewportWidth: CGFloat?

    func makeCoordinator() -> MailWebViewLoadGuard { MailWebViewLoadGuard() }

    func makeUIView(context: Context) -> WKWebView {
        configure(WKWebView())
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.shouldLoad(sandboxedHTML) else { return }
        webView.loadHTMLString(sandboxedHTML, baseURL: nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        HtmlMailWebView.constrainedSize(proposedWidth: proposal.width, proposedHeight: proposal.height,
                                        viewportHeight: viewportHeight, viewportWidth: viewportWidth)
    }
}
#endif

private func configure(_ webView: WKWebView) -> WKWebView {
    webView.configuration.preferences.javaScriptEnabled = false
    webView.allowsLinkPreview = false
    #if os(iOS)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.showsVerticalScrollIndicator = false
    #endif
    return webView
}
#endif
