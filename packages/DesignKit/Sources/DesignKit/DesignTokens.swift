import CoreKit
import SwiftUI

/// 设计规范 v1 · Blue Box Classic 的 token（docs/design/design-system.md，DESIGN-001/002 防漂移）。
/// 颜色以 UInt32 原始常量保存（可测试），Color/Font 为派生。
/// 视图层禁止绕过 token 内联颜色/字号（DESIGN-002 由 design_002 源码扫描锁）。
public enum DesignTokens {
    // MARK: 品牌与语义（§2）

    public static let brandBlueHex: UInt32 = 0x006FCF
    public static let brandBlueDeepHex: UInt32 = 0x0B4E96
    public static let brandBlueWashHex: UInt32 = 0xE8F1FB
    public static let brandBlueBorderHex: UInt32 = 0xCFE2F6
    public static let surfaceWashHex: UInt32 = 0xF7FAFE
    public static let surfaceSubtleHex: UInt32 = 0xF1F4F9
    public static let borderDefaultHex: UInt32 = 0xE8ECF3
    public static let borderHairlineHex: UInt32 = 0xF1F4F8
    public static let statusSuccessBgHex: UInt32 = 0xF0F7EE
    public static let statusSuccessFgHex: UInt32 = 0x2E7D32

    // MARK: 中性（§2）

    public static let inkPrimaryHex: UInt32 = 0x16202F
    public static let inkSecondaryHex: UInt32 = 0x3C4657
    public static let inkBodyHex: UInt32 = 0x2A3444
    public static let inkMutedHex: UInt32 = 0x8892A6
    public static let inkFaintHex: UInt32 = 0x9AA4B5
    public static let borderStrongHex: UInt32 = 0xD8DFEA

    // MARK: bucket 语义色（§2）

    public static let imboxHex: UInt32 = 0x006FCF
    public static let feedHex: UInt32 = 0xE8710A
    public static let paperTrailHex: UInt32 = 0x64748B
    public static let screenerHex: UInt32 = 0x7C3AED
    public static let setAsideHex: UInt32 = 0xC4A35A
    /// blocked（CLS-011）：不进导航，仅在纠正菜单与搜索结果出现——低调灰
    public static let blockedHex: UInt32 = 0x8892A6

    // MARK: 布局与形状（§4）

    public static let sidebarWidth: CGFloat = 212
    public static let listWidth: CGFloat = 392
    public static let selectionBarWidth: CGFloat = 3
    public static let titleBarHeight: CGFloat = 52
    public static let rowHeight: CGFloat = 68
    public static let avatarSize: CGFloat = 36

    /// 圆角：窗 14 / 面板内卡片·头像 10 / 按钮·徽章 8（§4；pill 用 Capsule）
    public static let radiusWindow: CGFloat = 14
    public static let radiusCard: CGFloat = 10
    public static let radiusButton: CGFloat = 8

    /// 间距节奏：栏内 16 / 面板内 20-30 / 阅读区左右 30（§4）
    public static let spacingColumn: CGFloat = 16
    public static let spacingPanel: CGFloat = 22
    public static let spacingReading: CGFloat = 30

    // MARK: 派生颜色

    public static var brandBlue: Color { Color(hex: brandBlueHex) }
    public static var brandBlueDeep: Color { Color(hex: brandBlueDeepHex) }
    public static var brandBlueWash: Color { Color(hex: brandBlueWashHex) }
    public static var brandBlueBorder: Color { Color(hex: brandBlueBorderHex) }
    public static var surfaceWash: Color { Color(hex: surfaceWashHex) }
    public static var surfaceSubtle: Color { Color(hex: surfaceSubtleHex) }
    public static var surfaceMain: Color { .white }
    public static var borderDefault: Color { Color(hex: borderDefaultHex) }
    public static var borderHairline: Color { Color(hex: borderHairlineHex) }
    public static var borderStrong: Color { Color(hex: borderStrongHex) }
    public static var statusSuccessBg: Color { Color(hex: statusSuccessBgHex) }
    public static var statusSuccessFg: Color { Color(hex: statusSuccessFgHex) }
    public static var inkPrimary: Color { Color(hex: inkPrimaryHex) }
    public static var inkSecondary: Color { Color(hex: inkSecondaryHex) }
    /// 阅读区正文（mockup r-content #2A3444）
    public static var inkBody: Color { Color(hex: inkBodyHex) }
    public static var inkMuted: Color { Color(hex: inkMutedHex) }
    public static var inkFaint: Color { Color(hex: inkFaintHex) }

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

    /// 主按钮阴影（§4：0 4px 14px rgba(0,111,207,.35)）
    public static func primaryShadow(_ color: Color = brandBlue) -> some ViewModifier {
        PrimaryShadowModifier(color: color)
    }

    private struct PrimaryShadowModifier: ViewModifier {
        let color: Color
        func body(content: Content) -> some View {
            content.shadow(color: color.opacity(0.35), radius: 7, x: 0, y: 4)
        }
    }

    // MARK: 排版阶梯（§3：SF Pro 系统栈，不打包字体文件）

    public enum Typo {
        /// Title 22/800：阅读页主题
        public static let title = Font.system(size: 22, weight: .heavy)
        /// Head 19/800：列表标题
        public static let head = Font.system(size: 19, weight: .heavy)
        /// Sub 16/800：阅读页发件人
        public static let sub = Font.system(size: 16, weight: .heavy)
        /// Body-strong 13.5/700：列表发件人
        public static let bodyStrong = Font.system(size: 13.5, weight: .bold)
        /// 导航项 13.5/500
        public static let navItem = Font.system(size: 13.5, weight: .medium)
        /// Body 14/400：邮件正文
        public static let body = Font.system(size: 14)
        /// Caption 12.5/600：列表主题、按钮
        public static let caption = Font.system(size: 12.5, weight: .semibold)
        /// Meta 11.5/500：预览行
        public static let meta = Font.system(size: 11.5, weight: .medium)
        /// Micro 10.5/700 +1.2 tracking 大写：分组标签
        public static let micro = Font.system(size: 10.5, weight: .bold)
        /// 设备码展示（等宽 40/800）
        public static let deviceCode = Font.system(size: 40, weight: .heavy, design: .monospaced)
        /// SF Symbol 图标尺度（非排版阶梯，按用途命名）
        public static let iconHero = Font.system(size: 56)
        public static let iconLarge = Font.system(size: 40)
        public static let iconMedium = Font.system(size: 28)
        public static let iconCompact = Font.system(size: 14, weight: .semibold)
        public static let iconTiny = Font.system(size: 11)
    }

    // MARK: 动效（§6：动画只表达归类语义；DESIGN-004）

    public enum Motion {
        /// 微交互 120ms
        public static let micro: TimeInterval = 0.12
        /// 视图转场 220ms
        public static let transition: TimeInterval = 0.22
        /// bucket 归类动画 320ms（spring）
        public static let classification: TimeInterval = 0.32
        public static let classificationSpringResponse: Double = 0.32
        public static let classificationSpringDamping: Double = 0.86

        /// 归类语义动画（邮件"飞入"目标桶）
        public static var classificationSpring: Animation {
            .spring(response: classificationSpringResponse,
                    dampingFraction: classificationSpringDamping)
        }

        /// 「减弱动态效果」降级：nil = 无动画（DESIGN-004）
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
}
