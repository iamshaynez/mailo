import Foundation
import SwiftUI

/// 阅读表面几何契约（DESIGN-006）。
enum ReaderSurfaceSpec {
    static let gradientLocations: [CGFloat] = [0, 0.42, 1]
    static let trailingGutter: CGFloat = 20
    static let bottomGutter: CGFloat = 16
    static let headerMeasure: CGFloat = 576
    static let cardTrailingAllowance: CGFloat = 28
}

/// 选中卡片跨栏阴影契约（DESIGN-006）。
enum ConnectionShadowSpec {
    static let blur: CGFloat = 8
    static let x: CGFloat = 3
    static let y: CGFloat = 4
    static let width: CGFloat = 24
    static let opacity = 0.32
}

/// 选中卡片在主壳坐标系中的位置；仅选中行上报（DESIGN-006）。
struct SelectedCardAnchorPreference: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// 阅读区的连续低振幅表面；空/加载/失败/正文共用（DESIGN-006）。
struct ReaderSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: DesignTokens.color(.readerHeader), location: ReaderSurfaceSpec.gradientLocations[0]),
                .init(color: DesignTokens.color(.readerBodyTop), location: ReaderSurfaceSpec.gradientLocations[1]),
                .init(color: DesignTokens.color(.readerBodyBottom), location: ReaderSurfaceSpec.gradientLocations[2]),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(stops: [
                .init(color: DesignTokens.color(.readerLeading), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: DesignTokens.color(.readerTrailing), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
                .opacity(0.28)
        }
    }
}

/// 主壳层接触阴影：只读取选中卡片 anchor，不参与布局或 hit-testing。
struct ConnectionShadow: View {
    let anchor: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
            .fill(DesignTokens.shadowColor)
            .frame(width: ConnectionShadowSpec.width, height: anchor.height + 12)
            .blur(radius: ConnectionShadowSpec.blur)
            .opacity(colorScheme == .light ? 0.12 : ConnectionShadowSpec.opacity)
            .position(x: anchor.maxX + ReaderSurfaceSpec.cardTrailingAllowance + ConnectionShadowSpec.x,
                      y: anchor.midY + ConnectionShadowSpec.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// WebView 文档变化门禁（PERF-005）。
final class MailWebViewLoadGuard {
    private var loadedDocument: String?

    func shouldLoad(_ document: String) -> Bool {
        guard document != loadedDocument else { return false }
        loadedDocument = document
        return true
    }
}

/// 阅读加载代际；旧任务即使晚完成也不能提交（JOURNEY-014 / PERF-005）。
struct ReaderLoadGate {
    private var generation = 0
    private var currentID: String?

    mutating func begin(_ stableId: String) -> Int {
        generation += 1
        currentID = stableId
        return generation
    }

    func canCommit(_ token: Int, for stableId: String) -> Bool {
        token == generation && stableId == currentID
    }
}
