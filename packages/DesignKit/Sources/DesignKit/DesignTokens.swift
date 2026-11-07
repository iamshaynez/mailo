import SwiftUI

import SwiftUI

/// 设计规范 v1 · Blue Box Classic 的 token（docs/design/design-system.md，DESIGN-001 防漂移）。
/// 颜色以 UInt32 原始常量保存（可测试），Color 为派生。
public enum DesignTokens {
    // 品牌与语义
    public static let brandBlueHex: UInt32 = 0x006FCF
    public static let brandBlueDeepHex: UInt32 = 0x0B4E96
    public static let brandBlueWashHex: UInt32 = 0xE8F1FB

    // bucket 语义色（§2）
    public static let imboxHex: UInt32 = 0x006FCF
    public static let feedHex: UInt32 = 0xE8710A
    public static let paperTrailHex: UInt32 = 0x64748B
    public static let screenerHex: UInt32 = 0x7C3AED
    public static let setAsideHex: UInt32 = 0xC4A35A

    // 布局（§4）
    public static let sidebarWidth: CGFloat = 212
    public static let listWidth: CGFloat = 392
    public static let selectionBarWidth: CGFloat = 3
    public static let titleBarHeight: CGFloat = 52

    public static var brandBlue: Color { Color(hex: brandBlueHex) }
    public static var brandBlueDeep: Color { Color(hex: brandBlueDeepHex) }
    public static var brandBlueWash: Color { Color(hex: brandBlueWashHex) }
    public static var inkPrimary: Color { Color(hex: 0x16202F) }
    public static var inkSecondary: Color { Color(hex: 0x3C4657) }
    public static var inkMuted: Color { Color(hex: 0x8892A6) }
    public static var surfaceMain: Color { .white }
    public static var borderDefault: Color { Color(hex: 0xE8ECF3) }

    public static func bucketColor(_ bucket: CoreKit.Bucket) -> Color {
        switch bucket {
        case .imbox: return Color(hex: imboxHex)
        case .feed: return Color(hex: feedHex)
        case .paperTrail: return Color(hex: paperTrailHex)
        case .screener: return Color(hex: screenerHex)
        case .setAside: return Color(hex: setAsideHex)
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
