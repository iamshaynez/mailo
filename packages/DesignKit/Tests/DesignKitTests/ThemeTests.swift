import Foundation
import SwiftUI
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（DESIGN-005 / JOURNEY-016）

@MainActor
struct ThemeTests {
    @Test("DESIGN-005 Slate Concept 双主题完整色板")
    func design_005_theme_palette() throws {
        let expected: [DesignTokens.ThemeRole: (light: UInt32, dark: UInt32)] = [
            .surfaceSidebar: (0xE9EDF3, 0x171D22),
            .surfaceToolbar: (0xE9EDF3, 0x171D22),
            .surfaceList: (0xF3F5F8, 0x171D24),
            .surfaceCard: (0xFFFFFF, 0x242933),
            .surfaceCardSelected: (0xFFFFFF, 0x2B323D),
            .surfaceReader: (0xFFFFFF, 0x3C4350),
            .readerLeading: (0xFAFCFF, 0x3B434F),
            .readerHeader: (0xFFFFFF, 0x3A424D),
            .readerBodyTop: (0xFCFDFF, 0x3D4551),
            .readerBodyBottom: (0xF6F8FB, 0x343C47),
            .readerTrailing: (0xF3F5F9, 0x38404B),
            .readerChip: (0xF0F3F7, 0x47505C),
            .cardSelectedBorder: (0xD8DEE7, 0x39424D),
            .surfaceControl: (0xE7ECF2, 0x2B3442),
            .surfaceHover: (0xEDF1F6, 0x2B323E),
            .surfaceSearch: (0xFFFFFF, 0xF6FAFF),
            .inkPrimary: (0x18202B, 0xF4F6FA),
            .inkSecondary: (0x4B5665, 0xB2BAC7),
            .inkBody: (0x283444, 0xD5DAE3),
            .inkMuted: (0x7A8594, 0x8791A1),
            .inkFaint: (0x9AA4B1, 0x606B7B),
            .borderDefault: (0xDDE3EB, 0x303845),
            .borderHairline: (0xE9EEF4, 0x262D38),
            .borderStrong: (0xC9D2DE, 0x4A5565),
            .brandBlue: (0x0078FF, 0x0078FF),
            .brandBlueDeep: (0x0B4E96, 0x75B9FF),
            .brandBlueWash: (0xE8F2FF, 0x1D3550),
            .brandBlueBorder: (0xC8E0FA, 0x2E537A),
            .statusSuccessBackground: (0xE7F5EC, 0x17372B),
            .statusSuccessForeground: (0x237A46, 0x4BCD8B),
            .statusDanger: (0xD94452, 0xFF6B74),
        ]

        #expect(Set(DesignTokens.ThemeRole.allCases) == Set(expected.keys))
        for role in DesignTokens.ThemeRole.allCases {
            let pair = try #require(expected[role])
            #expect(DesignTokens.hex(role, for: .light) == pair.light, "\(role) light")
            #expect(DesignTokens.hex(role, for: .dark) == pair.dark, "\(role) dark")
        }
    }

    @Test("DESIGN-005 / JOURNEY-016 外观偏好默认值、rawValue 与本地持久化")
    func design_005_appearance_preference() throws {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
        #expect(AppearancePreference.allCases.count == 3)

        let suite = "DesignKitTests.Appearance.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(AppearancePreference.load(from: defaults) == .system)
        AppearancePreference.dark.save(to: defaults)
        #expect(AppearancePreference.load(from: defaults) == .dark)
        #expect(defaults.string(forKey: AppearancePreference.storageKey) == "dark")
        AppearancePreference.light.save(to: defaults)
        #expect(AppearancePreference.load(from: defaults) == .light)
    }

    @Test("DESIGN-005 控件 default/hover/pressed/focus/disabled 状态 token")
    func design_005_control_states() {
        let normal = DesignTokens.controlState(.normal)
        let hover = DesignTokens.controlState(.hover)
        let pressed = DesignTokens.controlState(.pressed)
        let focused = DesignTokens.controlState(.focused)
        let disabled = DesignTokens.controlState(.disabled)

        #expect(normal.opacity == 1 && normal.scale == 1 && !normal.showsFocusRing)
        #expect(hover.opacity == 1 && hover.scale == 1)
        #expect(pressed.scale == 0.98 && pressed.opacity == 0.88)
        #expect(focused.showsFocusRing)
        #expect(disabled.opacity == 0.45 && disabled.scale == 1)
    }
}
