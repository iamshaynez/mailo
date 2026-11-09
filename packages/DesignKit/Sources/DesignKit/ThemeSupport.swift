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

    /// 从注入的 defaults 恢复；缺失或非法值安全回落 system。
    public static func load(from defaults: UserDefaults) -> AppearancePreference {
        defaults.string(forKey: storageKey).flatMap(AppearancePreference.init(rawValue:)) ?? .system
    }

    /// 持久化到注入的 defaults，便于测试与所有窗口共享。
    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

private struct MailoThemeModifier: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var rawAppearance = AppearancePreference.system.rawValue

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

    /// Slate Concept v2 原始色板（DESIGN-005；docs/design/design-system.md §2）。
    public static func hex(_ role: ThemeRole, for scheme: ColorScheme) -> UInt32 {
        switch (role, scheme) {
        case (.surfaceSidebar, .light), (.surfaceToolbar, .light): return 0xE9EDF3
        case (.surfaceSidebar, .dark), (.surfaceToolbar, .dark): return 0x171D22
        case (.surfaceList, .light): return 0xF3F5F8
        case (.surfaceList, .dark): return 0x171D24
        case (.surfaceCard, .light), (.surfaceCardSelected, .light), (.surfaceReader, .light): return 0xFFFFFF
        case (.surfaceCard, .dark): return 0x242933
        case (.surfaceCardSelected, .dark): return 0x2B323D
        case (.surfaceReader, .dark): return 0x3C4350
        case (.readerLeading, .light): return 0xFAFCFF
        case (.readerLeading, .dark): return 0x3B434F
        case (.readerHeader, .light): return 0xFFFFFF
        case (.readerHeader, .dark): return 0x3A424D
        case (.readerBodyTop, .light): return 0xFCFDFF
        case (.readerBodyTop, .dark): return 0x3D4551
        case (.readerBodyBottom, .light): return 0xF6F8FB
        case (.readerBodyBottom, .dark): return 0x343C47
        case (.readerTrailing, .light): return 0xF3F5F9
        case (.readerTrailing, .dark): return 0x38404B
        case (.readerChip, .light): return 0xF0F3F7
        case (.readerChip, .dark): return 0x47505C
        case (.cardSelectedBorder, .light): return 0xD8DEE7
        case (.cardSelectedBorder, .dark): return 0x39424D
        case (.surfaceControl, .light): return 0xE7ECF2
        case (.surfaceControl, .dark): return 0x2B3442
        case (.surfaceHover, .light): return 0xEDF1F6
        case (.surfaceHover, .dark): return 0x2B323E
        case (.surfaceSearch, .light): return 0xFFFFFF
        case (.surfaceSearch, .dark): return 0xF6FAFF
        case (.inkPrimary, .light): return 0x18202B
        case (.inkPrimary, .dark): return 0xF4F6FA
        case (.inkSecondary, .light): return 0x4B5665
        case (.inkSecondary, .dark): return 0xB2BAC7
        case (.inkBody, .light): return 0x283444
        case (.inkBody, .dark): return 0xD5DAE3
        case (.inkMuted, .light): return 0x7A8594
        case (.inkMuted, .dark): return 0x8791A1
        case (.inkFaint, .light): return 0x9AA4B1
        case (.inkFaint, .dark): return 0x606B7B
        case (.borderDefault, .light): return 0xDDE3EB
        case (.borderDefault, .dark): return 0x303845
        case (.borderHairline, .light): return 0xE9EEF4
        case (.borderHairline, .dark): return 0x262D38
        case (.borderStrong, .light): return 0xC9D2DE
        case (.borderStrong, .dark): return 0x4A5565
        case (.brandBlue, _): return 0x0078FF
        case (.brandBlueDeep, .light): return 0x0B4E96
        case (.brandBlueDeep, .dark): return 0x75B9FF
        case (.brandBlueWash, .light): return 0xE8F2FF
        case (.brandBlueWash, .dark): return 0x1D3550
        case (.brandBlueBorder, .light): return 0xC8E0FA
        case (.brandBlueBorder, .dark): return 0x2E537A
        case (.statusSuccessBackground, .light): return 0xE7F5EC
        case (.statusSuccessBackground, .dark): return 0x17372B
        case (.statusSuccessForeground, .light): return 0x237A46
        case (.statusSuccessForeground, .dark): return 0x4BCD8B
        case (.statusDanger, .light): return 0xD94452
        case (.statusDanger, .dark): return 0xFF6B74
        @unknown default:
            return 0x0078FF
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
