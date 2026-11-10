import Testing
import Foundation
import CoreKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-001 / DESIGN-001）

@MainActor
struct DesignKitTests {

    @Test("JOURNEY-001 骨架端到端装配")
    func journey_001_bootstrap_end_to_end() async throws {
        let model = await MailoAppModel.bootstrapDemo()

        // roster 命中的三桶各就各位
        try model.load(bucket: .feed)
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.fromAddress == "alerts@netflix.com")

        try model.load(bucket: .paperTrail)
        #expect(model.entries.count == 1)

        try model.load(bucket: .imbox)
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.subject == "Re: contract")

        // 未知发件人：模型低置信 → Screener 待定（CLS-004 语义）
        #expect(model.screenerCount == 1)
    }

    @Test("DESIGN-001 Amex Blue token 与规范一致")
    func design_001_tokens_match_spec() {
        #expect(DesignTokens.accentHex == 0x0077C8)
        #expect(DesignTokens.surfaceSidebarHex == 0x071C2C)
        #expect(DesignTokens.sidebarActiveHex == 0x123A52)
        #expect(DesignTokens.hex(.surfaceList, for: .light) == 0xFFFFFF)
        #expect(DesignTokens.imboxHex == 0x0077C8)
        #expect(DesignTokens.feedHex == 0xE8710A)
        #expect(DesignTokens.paperTrailHex == 0x64748B)
        #expect(DesignTokens.screenerHex == 0x9561D9)
        #expect(DesignTokens.setAsideHex == 0xC4A35A)
        #expect(DesignTokens.sidebarWidth == 198)
        #expect(DesignTokens.listWidth == 492)
        #expect(DesignTokens.selectionBarWidth == 3)
        #expect(DesignTokens.titleBarHeight == 42)
    }

    @Test("DESIGN-001 侧栏与欢迎页共用 m + 圆点品牌组件")
    func design_001_shared_brand_mark() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignKit")
        let sidebar = try String(contentsOf: sources.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        let setup = try String(contentsOf: sources.appendingPathComponent("AccountSetupView.swift"), encoding: .utf8)
        #expect(sidebar.contains("MailoBrandMark()"))
        #expect(setup.contains("MailoBrandMark()"))
        #expect(!sidebar.contains("Canvas {"), "不再使用多色 Canvas M")
    }
}
