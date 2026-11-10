import CoreKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Inbox Reference v3 token（docs/design/design-system.md；DESIGN-001/002/005 防漂移）。
/// 原始 hex 可测试，动态 Color/Font 均由 token 派生；视图禁止内联颜色和字号。
public enum DesignTokens {
    // MARK: 浅色兼容常量与 bucket 语义（§2）

    /// 历史标识保留给既有调用；新视图优先使用 `accent`。
    public static let brandBlueHex: UInt32 = 0x0077C8
    public static let accentHex: UInt32 = brandBlueHex
    public static let brandBlueDeepHex: UInt32 = 0x005A9C
    public static let brandBlueWashHex: UInt32 = 0xE9F4FC
    public static let brandBlueBorderHex: UInt32 = 0xB8DDF3
    public static let surfaceSidebarHex: UInt32 = 0x071C2C
    public static let sidebarActiveHex: UInt32 = 0x123A52
    public static let sidebarInkHex: UInt32 = 0xF3F8FC
    public static let sidebarMutedHex: UInt32 = 0x8BA8BC
    public static let surfaceWashHex: UInt32 = 0xF4F7F9
    public static let surfaceSubtleHex: UInt32 = 0xEDF2F6
    public static let borderDefaultHex: UInt32 = 0xDCE5EB
    public static let borderHairlineHex: UInt32 = 0xE8EEF2
    public static let statusSuccessBgHex: UInt32 = 0xE7F5EC
    public static let statusSuccessFgHex: UInt32 = 0x237A46

    public static let inkPrimaryHex: UInt32 = 0x14232E
    public static let inkSecondaryHex: UInt32 = 0x4B5F6E
    public static let inkBodyHex: UInt32 = 0x2C3E4B
    public static let inkMutedHex: UInt32 = 0x7E919E
    public static let inkFaintHex: UInt32 = 0xA1AEB8
    public static let borderStrongHex: UInt32 = 0xC4D3DD

    public static let imboxHex: UInt32 = 0x0077C8
    public static let feedHex: UInt32 = 0xE8710A
    public static let paperTrailHex: UInt32 = 0x64748B
    public static let screenerHex: UInt32 = 0x9561D9
    public static let setAsideHex: UInt32 = 0xC4A35A
    /// blocked（CLS-011）：不进导航，仅在纠正菜单与搜索结果出现。
    public static let blockedHex: UInt32 = 0x8892A6

    // MARK: 布局与形状（§4）

    public static let sidebarMinWidth: CGFloat = 176
    public static let sidebarWidth: CGFloat = 198
    public static let sidebarMaxWidth: CGFloat = 216
    public static let listMinWidth: CGFloat = 360
    public static let listWidth: CGFloat = 492
    public static let listMaxWidth: CGFloat = 560
    public static let selectionBarWidth: CGFloat = 3
    public static let titleBarHeight: CGFloat = 42
    public static let searchHeight: CGFloat = 42
    public static let rowHeight: CGFloat = 98
    public static let avatarSize: CGFloat = 26
    public static let readerAvatarSize: CGFloat = 26
    public static let readingMeasure: CGFloat = 600
    public static let quickReplyHeight: CGFloat = 60
    public static let quickReplyExpandedHeight: CGFloat = 108
    public static let replySendHeight: CGFloat = 30
    public static let attachmentTileWidth: CGFloat = 104
    public static let attachmentTileHeight: CGFloat = 100

    public static let radiusWindow: CGFloat = 14
    public static let radiusCard: CGFloat = 8
    public static let radiusButton: CGFloat = 10
    public static let radiusSearch: CGFloat = 8
    public static let radiusChip: CGFloat = 6
    public static let radiusMedia: CGFloat = 8

    public static let spacingColumn: CGFloat = 16
    public static let spacingPanel: CGFloat = 18
    public static let spacingReading: CGFloat = 32
    public static let cardSpacing: CGFloat = 12

    // MARK: 动态语义颜色

    public static var accent: Color { color(.brandBlue) }
    public static var accentDeep: Color { color(.brandBlueDeep) }
    public static var accentWash: Color { color(.brandBlueWash) }
    public static var accentBorder: Color { color(.brandBlueBorder) }
    public static var brandBlue: Color { accent }
    public static var brandBlueDeep: Color { accentDeep }
    public static var brandBlueWash: Color { accentWash }
    public static var brandBlueBorder: Color { accentBorder }
    public static var surfaceSidebar: Color { color(.surfaceSidebar) }
    public static var surfaceToolbar: Color { color(.surfaceToolbar) }
    public static var surfaceList: Color { color(.surfaceList) }
    public static var surfaceCard: Color { color(.surfaceCard) }
    public static var surfaceCardSelected: Color { color(.surfaceCardSelected) }
    public static var cardSelectedBorder: Color { color(.cardSelectedBorder) }
    public static var readerChip: Color { color(.readerChip) }
    public static var surfaceReader: Color { color(.surfaceReader) }
    public static var surfaceControl: Color { color(.surfaceControl) }
    public static var surfaceHover: Color { color(.surfaceHover) }
    public static var surfaceSearch: Color { color(.surfaceSearch) }
    public static var surfaceWash: Color { color(.surfaceHover) }
    public static var surfaceSubtle: Color { color(.surfaceControl) }
    public static var surfaceMain: Color { color(.surfaceCard) }
    public static var borderDefault: Color { color(.borderDefault) }
    public static var borderHairline: Color { color(.borderHairline) }
    public static var borderStrong: Color { color(.borderStrong) }
    public static var statusSuccessBg: Color { color(.statusSuccessBackground) }
    public static var statusSuccessFg: Color { color(.statusSuccessForeground) }
    public static var statusDanger: Color { color(.statusDanger) }
    public static var inkPrimary: Color { color(.inkPrimary) }
    public static var inkSecondary: Color { color(.inkSecondary) }
    public static var inkBody: Color { color(.inkBody) }
    public static var inkMuted: Color { color(.inkMuted) }
    public static var inkFaint: Color { color(.inkFaint) }
    public static var sidebarActive: Color { Color(hex: sidebarActiveHex) }
    public static var sidebarInk: Color { Color(hex: sidebarInkHex) }
    public static var sidebarMuted: Color { Color(hex: sidebarMutedHex) }
    /// 参考图 Send 使用固定白字。
    public static var onAccent: Color { Color(hex: 0xFFFFFF) }
    public static var searchInk: Color { inkPrimary }
    public static var searchMuted: Color { inkMuted }
    public static var shadowColor: Color { Color(hex: 0x050A14) }

    public static func bucketColor(_ bucket: CoreKit.Bucket) -> Color {
        switch bucket {
        case .imbox: return Color(hex: imboxHex)
        case .feed: return Color(hex: feedHex)
        case .paperTrail: return Color(hex: paperTrailHex)
        case .screener: return Color(hex: screenerHex)
        case .setAside: return Color(hex: setAsideHex)
        case .blocked: return Color(hex: blockedHex)
        }
    }

    /// 主按钮阴影（§4）：轻微接触阴影，无 glow。
    public static func primaryShadow(_ color: Color = accent) -> some ViewModifier {
        PrimaryShadowModifier(color: color)
    }

    private struct PrimaryShadowModifier: ViewModifier {
        let color: Color
        func body(content: Content) -> some View {
            content.shadow(color: color.opacity(0.18), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: 排版阶梯（§3：SF Pro 系统栈）

    public enum Typo {
        public static let title = Font.system(size: 20, weight: .semibold)
        public static let head = Font.system(size: 16, weight: .semibold)
        public static let sub = Font.system(size: 15, weight: .semibold)
        public static let bodyStrong = Font.system(size: 13, weight: .semibold)
        public static let navItem = Font.system(size: 12.5, weight: .medium)
        public static let body = Font.system(size: 14)
        public static let caption = Font.system(size: 12, weight: .semibold)
        public static let meta = Font.system(size: 11)
        public static let micro = Font.system(size: 9.5, weight: .semibold)
        public static let deviceCode = Font.system(size: 40, weight: .heavy, design: .monospaced)
        public static let iconHero = Font.system(size: 56)
        public static let iconLarge = Font.system(size: 40)
        public static let iconMedium = Font.system(size: 28)
        public static let iconCompact = Font.system(size: 14, weight: .semibold)
        public static let iconSmall = Font.system(size: 12, weight: .medium)
        public static let iconTiny = Font.system(size: 11)
    }

    // MARK: 动效（§6；DESIGN-004）

    public enum Motion {
        public static let micro: TimeInterval = 0.12
        public static let transition: TimeInterval = 0.22
        public static let classification: TimeInterval = 0.32
        public static let classificationSpringResponse: Double = 0.32
        public static let classificationSpringDamping: Double = 0.86
        public static let readerTranslation: CGFloat = 6

        public static var classificationSpring: Animation {
            .spring(response: classificationSpringResponse,
                    dampingFraction: classificationSpringDamping)
        }

        /// 阅读切换位移；Reduce Motion 时位移也归零。
        public static func readerOffset(reduceMotion: Bool) -> CGFloat {
            reduceMotion ? 0 : readerTranslation
        }

        /// 减弱动态效果降级：nil = 无动画（DESIGN-004）。
        public static func animation(duration: TimeInterval, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: duration)
        }

        public static func spring(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : classificationSpring
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// SPM 内不依赖 asset catalog 的双主题动态色（DESIGN-005）。
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(mailoHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let darkActive = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(mailoHex: darkActive ? dark : light)
        })
        #else
        self.init(hex: light)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(mailoHex: UInt32) {
        self.init(red: CGFloat((mailoHex >> 16) & 0xFF) / 255,
                  green: CGFloat((mailoHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(mailoHex & 0xFF) / 255,
                  alpha: 1)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(mailoHex: UInt32) {
        self.init(calibratedRed: CGFloat((mailoHex >> 16) & 0xFF) / 255,
                  green: CGFloat((mailoHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(mailoHex & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif
