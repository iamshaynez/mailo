import Foundation
import SwiftUI
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（DESIGN-005 / JOURNEY-016）

@MainActor
struct ThemeTests {
    @Test("DESIGN-005 Amex Blue 双主题完整色板")
    func design_005_theme_palette() throws {
        let expected: [DesignTokens.ThemeRole: (light: UInt32, dark: UInt32)] = [
            .surfaceSidebar: (0x071C2C, 0x071C2C),
            .surfaceToolbar: (0xFFFFFF, 0x111E28),
            .surfaceList: (0xFFFFFF, 0x15232D),
            .surfaceCard: (0xFFFFFF, 0x1F303C),
            .surfaceCardSelected: (0xFFFFFF, 0x24445A),
            .surfaceReader: (0xFFFFFF, 0x1B2A35),
            .readerLeading: (0xFFFFFF, 0x1B2A35),
            .readerHeader: (0xFFFFFF, 0x1B2A35),
            .readerBodyTop: (0xFFFFFF, 0x1B2A35),
            .readerBodyBottom: (0xFAFCFD, 0x16242E),
            .readerTrailing: (0xF4F8FA, 0x15222B),
            .readerChip: (0xEFF4F7, 0x2B3E4B),
            .cardSelectedBorder: (0xE0E9EF, 0x3B5363),
            .surfaceControl: (0xEDF2F6, 0x253743),
            .surfaceHover: (0xF4F7F9, 0x263E4D),
            .surfaceSearch: (0xF5F8FA, 0x24343F),
            .inkPrimary: (0x14232E, 0xF0F7FB),
            .inkSecondary: (0x4B5F6E, 0xB6C6D1),
            .inkBody: (0x2C3E4B, 0xD4E0E7),
            .inkMuted: (0x7E919E, 0x8FA5B3),
            .inkFaint: (0xA1AEB8, 0x617885),
            .borderDefault: (0xDCE5EB, 0x31444F),
            .borderHairline: (0xE8EEF2, 0x273842),
            .borderStrong: (0xC4D3DD, 0x4A616F),
            .brandBlue: (0x0077C8, 0x45B7E8),
            .brandBlueDeep: (0x005A9C, 0x7CCCEC),
            .brandBlueWash: (0xE9F4FC, 0x12384D),
            .brandBlueBorder: (0xB8DDF3, 0x24566E),
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

        #expect(AppearancePreference.load(from: defaults) == .light)
        AppearancePreference.dark.save(to: defaults)
        #expect(AppearancePreference.load(from: defaults) == .dark)
        #expect(defaults.string(forKey: AppearancePreference.storageKey) == "dark")
        AppearancePreference.light.save(to: defaults)
        #expect(AppearancePreference.load(from: defaults) == .light)
    }

    @Test("DESIGN-005 主邮件窗口即使保存 Dark 也固定 Light")
    func design_005_reference_window_forces_light() {
        #expect(MailoReferenceTheme.colorScheme == .light)
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
