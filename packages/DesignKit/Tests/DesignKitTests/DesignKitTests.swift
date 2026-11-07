import Testing
import CoreKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-001 / DESIGN-001）

@MainActor
struct DesignKitTests {

    @Test("JOURNEY-001 骨架端到端装配")
    func journey_001_bootstrap_end_to_end() throws {
        let model = MailoAppModel.bootstrapDemo()

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

    @Test("DESIGN-001 设计 token 与规范一致")
    func design_001_tokens_match_spec() {
        #expect(DesignTokens.brandBlueHex == 0x006FCF)      // 运通蓝
        #expect(DesignTokens.imboxHex == 0x006FCF)
        #expect(DesignTokens.feedHex == 0xE8710A)
        #expect(DesignTokens.paperTrailHex == 0x64748B)
        #expect(DesignTokens.screenerHex == 0x7C3AED)
        #expect(DesignTokens.setAsideHex == 0xC4A35A)
        #expect(DesignTokens.sidebarWidth == 212)
        #expect(DesignTokens.listWidth == 392)
        #expect(DesignTokens.selectionBarWidth == 3)
        #expect(DesignTokens.titleBarHeight == 52)
    }
}
