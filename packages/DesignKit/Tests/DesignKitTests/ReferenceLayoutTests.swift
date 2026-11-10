import CoreKit
import CoreGraphics
import Testing

@testable import DesignKit

@MainActor
struct ReferenceLayoutTests {
    @Test("DESIGN-007 Inbox Reference 几何 token 与比例")
    func design_007_reference_layout_metrics() {
        #expect(DesignTokens.sidebarWidth == 198)
        #expect(DesignTokens.listWidth == 492)
        #expect(DesignTokens.titleBarHeight == 42)
        #expect(DesignTokens.rowHeight == 98)
        #expect(DesignTokens.avatarSize == 26)
        #expect(DesignTokens.readerAvatarSize == 26)
        #expect(DesignTokens.readingMeasure == 600)
        #expect(DesignTokens.quickReplyHeight == 60)
        #expect(DesignTokens.quickReplyExpandedHeight == 108)
        #expect(DesignTokens.replySendHeight == 30)
        #expect(DesignTokens.attachmentTileWidth == 104)
        #expect(DesignTokens.attachmentTileHeight == 100)
        #expect(DesignTokens.sidebarActiveHex == 0x123A52)

        let reference = ReferenceLayout.columns(totalWidth: 898)
        #expect(reference.sidebar == 139 && reference.list == 345 && reference.reader == 414)
        let minimum = ReferenceLayout.columns(totalWidth: 960)
        #expect(minimum.sidebar == 149 && minimum.list == 369 && minimum.reader == 442)
    }

    @Test("DESIGN-007/JOURNEY-014 正文视口扣除头部和回复区且始终有限")
    func design_007_reader_body_viewport() {
        #expect(ReferenceLayout.bodyHeight(viewportHeight: 652, headerHeight: 180, replyHeight: 64) == 408)
        #expect(ReferenceLayout.bodyHeight(viewportHeight: 260, headerHeight: 180, replyHeight: 124) == 160)
        #expect(ReferenceLayout.contentWidth(containerWidth: 668) == 600)
        #expect(ReferenceLayout.contentWidth(containerWidth: 332) == 268)
        #expect(ReferenceLayout.contentWidth(containerWidth: 32) == 0)
    }

    @Test("DESIGN-007 发件人显示名与地址分离")
    func design_007_sender_presentation() {
        let named = SenderPresentation("John Appendix <john@example.com>")
        #expect(named.name == "John Appendix")
        #expect(named.address == "john@example.com")
        let plain = SenderPresentation("sarah@wave.co")
        #expect(plain.name == "sarah@wave.co")
        #expect(plain.address == "sarah@wave.co")
    }

    @Test("DESIGN-007 参考 Demo 六封混合邮件与三张真实 MIME 图片")
    func design_007_reference_demo_fixture() async throws {
        let model = await MailoAppModel.bootstrapReferenceDemo()
        #expect(model.entries.count == 6)
        #expect(SenderPresentation(model.entries.first?.fromAddress).name == "Penny Singh")
        #expect(model.entries.contains { $0.flags.contains("\\Seen") })
        #expect(model.entries.contains { !$0.flags.contains("\\Seen") })
        let john = try #require(model.entries.first { $0.subject?.contains("Visual Design") == true })
        guard case .loaded(let detail) = await model.loadDetail(stableId: john.stableId) else {
            Issue.record("参考邮件应加载成功"); return
        }
        #expect(detail.textBody?.contains("Hello Bagdad") == true)
        #expect(detail.attachments.count == 3)
        #expect(detail.attachments.allSatisfy { $0.contentType == "image/png" && !$0.body.isEmpty })
    }

    @Test("DESIGN-006 图片附件保留真实数据，其他附件使用类型占位")
    func design_006_attachment_presentation() {
        let bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let image = MailAttachmentPreview(part: MimePart(body: bytes, contentType: "image/png", filename: "mountain.png"))
        #expect(image.isImage)
        #expect(image.data == bytes)
        #expect(image.filename == "mountain.png")

        let document = MailAttachmentPreview(part: MimePart(body: [1], contentType: "application/pdf", filename: "brief.pdf"))
        #expect(!document.isImage)
        #expect(document.symbolName == "doc.text.fill")
    }
}
