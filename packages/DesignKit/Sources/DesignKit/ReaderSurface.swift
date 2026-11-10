import Foundation
import SwiftUI

/// 阅读纸面几何契约（DESIGN-006/007）。
enum ReaderSurfaceSpec {
    static let usesGradient = false
    static let horizontalPadding: CGFloat = 20
    static let leadingPadding: CGFloat = 20
    static let trailingPadding: CGFloat = 44
    static let trailingGutter: CGFloat = 0
    static let bottomGutter: CGFloat = 0
    static let headerMeasure: CGFloat = 600
}

/// 原图邮件层次的阴影契约（DESIGN-002）；只作用于背景表面，不参与布局。
enum MailElevationSpec {
    static let headerRadius: CGFloat = 6
    static let headerY: CGFloat = 3
    static let rowRadius: CGFloat = 6
    static let rowY: CGFloat = 3
    static let selectedRadius: CGFloat = 14
    static let selectedY: CGFloat = 4
    static let paneRadius: CGFloat = 12
    static let paneX: CGFloat = 4
    static let headerOpacity = 0.06
    static let rowOpacity = 0.06
    static let selectedOpacity = 0.12
    static let paneOpacity = 0.10
}

/// 阅读区的平坦纸面；空/加载/失败/正文共用（DESIGN-006）。
struct ReaderSurface: View {
    var body: some View {
        DesignTokens.surfaceReader
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
