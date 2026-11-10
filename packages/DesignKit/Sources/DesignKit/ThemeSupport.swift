import Foundation
import SwiftUI

/// 外观偏好（DESIGN-005 / JOURNEY-016）：System 默认，rawValue 用于本地持久化。
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "mailo.appearance"
    public var id: String { rawValue }

    /// SwiftUI 覆盖值；system 返回 nil，继续跟随系统。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 从注入的 defaults 恢复；参考图基线下缺失或非法值回落 light，显式 System 仍跟随系统。
    public static func load(from defaults: UserDefaults) -> AppearancePreference {
        defaults.string(forKey: storageKey).flatMap(AppearancePreference.init(rawValue:)) ?? .light
    }

    /// 持久化到注入的 defaults，便于测试与所有窗口共享。
    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

/// 主邮件窗口固定使用参考图浅色；Compose/Settings 仍走用户偏好（DESIGN-005）。
enum MailoReferenceTheme {
    static let colorScheme: ColorScheme = .light
}

private struct MailoThemeModifier: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var rawAppearance = AppearancePreference.light.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(AppearancePreference(rawValue: rawAppearance)?.colorScheme)
    }
}

extension View {
    /// 将持久化外观应用到任意 scene/sheet（DESIGN-005 / JOURNEY-016）。
    public func mailoAppearance() -> some View {
        modifier(MailoThemeModifier())
    }
}

extension DesignTokens {
    /// 可测试的语义色角色（DESIGN-005）。
    public enum ThemeRole: String, CaseIterable, Hashable, Sendable {
        case surfaceSidebar, surfaceToolbar, surfaceList, surfaceCard, surfaceCardSelected
        case surfaceReader, surfaceControl, surfaceHover, surfaceSearch
        case readerLeading, readerHeader, readerBodyTop, readerBodyBottom, readerTrailing, readerChip
        case cardSelectedBorder
        case inkPrimary, inkSecondary, inkBody, inkMuted, inkFaint
        case borderDefault, borderHairline, borderStrong
        case brandBlue, brandBlueDeep, brandBlueWash, brandBlueBorder
        case statusSuccessBackground, statusSuccessForeground, statusDanger
    }

    /// Inbox Reference v3 原始色板（DESIGN-005；docs/design/design-system.md §2）。
    public static func hex(_ role: ThemeRole, for scheme: ColorScheme) -> UInt32 {
        switch (role, scheme) {
        case (.surfaceSidebar, _): return 0x071C2C
        case (.surfaceToolbar, .light): return 0xFFFFFF
        case (.surfaceToolbar, .dark): return 0x111E28
        case (.surfaceList, .light): return 0xFFFFFF
        case (.surfaceList, .dark): return 0x15232D
        case (.surfaceCard, .light), (.surfaceCardSelected, .light), (.surfaceReader, .light): return 0xFFFFFF
        case (.surfaceCard, .dark): return 0x1F303C
        case (.surfaceCardSelected, .dark): return 0x24445A
        case (.surfaceReader, .dark): return 0x1B2A35
        case (.readerLeading, .light): return 0xFFFFFF
        case (.readerLeading, .dark): return 0x1B2A35
        case (.readerHeader, .light): return 0xFFFFFF
        case (.readerHeader, .dark): return 0x1B2A35
        case (.readerBodyTop, .light): return 0xFFFFFF
        case (.readerBodyTop, .dark): return 0x1B2A35
        case (.readerBodyBottom, .light): return 0xFAFCFD
        case (.readerBodyBottom, .dark): return 0x16242E
        case (.readerTrailing, .light): return 0xF4F8FA
        case (.readerTrailing, .dark): return 0x15222B
        case (.readerChip, .light): return 0xEFF4F7
        case (.readerChip, .dark): return 0x2B3E4B
        case (.cardSelectedBorder, .light): return 0xE0E9EF
        case (.cardSelectedBorder, .dark): return 0x3B5363
        case (.surfaceControl, .light): return 0xEDF2F6
        case (.surfaceControl, .dark): return 0x253743
        case (.surfaceHover, .light): return 0xF4F7F9
        case (.surfaceHover, .dark): return 0x263E4D
        case (.surfaceSearch, .light): return 0xF5F8FA
        case (.surfaceSearch, .dark): return 0x24343F
        case (.inkPrimary, .light): return 0x14232E
        case (.inkPrimary, .dark): return 0xF0F7FB
        case (.inkSecondary, .light): return 0x4B5F6E
        case (.inkSecondary, .dark): return 0xB6C6D1
        case (.inkBody, .light): return 0x2C3E4B
        case (.inkBody, .dark): return 0xD4E0E7
        case (.inkMuted, .light): return 0x7E919E
        case (.inkMuted, .dark): return 0x8FA5B3
        case (.inkFaint, .light): return 0xA1AEB8
        case (.inkFaint, .dark): return 0x617885
        case (.borderDefault, .light): return 0xDCE5EB
        case (.borderDefault, .dark): return 0x31444F
        case (.borderHairline, .light): return 0xE8EEF2
        case (.borderHairline, .dark): return 0x273842
        case (.borderStrong, .light): return 0xC4D3DD
        case (.borderStrong, .dark): return 0x4A616F
        case (.brandBlue, .light): return 0x0077C8
        case (.brandBlue, .dark): return 0x45B7E8
        case (.brandBlueDeep, .light): return 0x005A9C
        case (.brandBlueDeep, .dark): return 0x7CCCEC
        case (.brandBlueWash, .light): return 0xE9F4FC
        case (.brandBlueWash, .dark): return 0x12384D
        case (.brandBlueBorder, .light): return 0xB8DDF3
        case (.brandBlueBorder, .dark): return 0x24566E
        case (.statusSuccessBackground, .light): return 0xE7F5EC
        case (.statusSuccessBackground, .dark): return 0x17372B
        case (.statusSuccessForeground, .light): return 0x237A46
        case (.statusSuccessForeground, .dark): return 0x4BCD8B
        case (.statusDanger, .light): return 0xD94452
        case (.statusDanger, .dark): return 0xFF6B74
        @unknown default:
            return 0x0077C8
        }
    }

    private static let dynamicThemeColors: [ThemeRole: Color] = {
        Dictionary(uniqueKeysWithValues: ThemeRole.allCases.map { role in
            (role, Color(light: hex(role, for: .light), dark: hex(role, for: .dark)))
        })
    }()

    /// 从语义角色返回复用的动态色；仍随 scene 外观变化（DESIGN-005 / PERF-005）。
    public static func color(_ role: ThemeRole) -> Color {
        dynamicThemeColors[role] ?? Color(light: hex(role, for: .light), dark: hex(role, for: .dark))
    }

    public enum ControlVisualState: Equatable, Sendable {
        case normal, hover, pressed, focused, disabled
    }

    /// 控件的非颜色状态面；颜色仍由 ThemeRole 提供（DESIGN-005）。
    public struct ControlStateToken: Equatable, Sendable {
        public let opacity: Double
        public let scale: CGFloat
        public let showsFocusRing: Bool

        public init(opacity: Double, scale: CGFloat, showsFocusRing: Bool) {
            self.opacity = opacity
            self.scale = scale
            self.showsFocusRing = showsFocusRing
        }
    }

    /// 所有共享按钮共用的状态映射（DESIGN-005）。
    public static func controlState(_ state: ControlVisualState) -> ControlStateToken {
        switch state {
        case .normal, .hover:
            return ControlStateToken(opacity: 1, scale: 1, showsFocusRing: false)
        case .pressed:
            return ControlStateToken(opacity: 0.88, scale: 0.98, showsFocusRing: false)
        case .focused:
            return ControlStateToken(opacity: 1, scale: 1, showsFocusRing: true)
        case .disabled:
            return ControlStateToken(opacity: 0.45, scale: 1, showsFocusRing: false)
        }
    }
}
