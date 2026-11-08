import Testing
import CoreKit
import Foundation
import MailProtoKit
@testable import DesignKit

// MARK: - 用例库：CLS-010 / STORE-006 / JOURNEY-003

@MainActor
struct ModelSupportTests {

    private func makeModel() -> (MailoAppModel, FakeImapServer) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("support-\(UUID().uuidString)", isDirectory: true)
        let model = MailoAppModel.createLive(storeDirectory: dir)
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 1, messages: [
            Message(uid: 1, flags: [], raw: Array("Message-ID: <s1@x.t>\r\nFrom: news@netflix.com\r\nSubject: S1\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\n\r\nbody one two three".utf8)),
            Message(uid: 2, flags: [], raw: Array("Message-ID: <s2@x.t>\r\nFrom: stranger@unknown.io\r\nSubject: mystery\r\nDate: Fri, 7 Nov 2026 11:00:00 +0000\r\n\r\nmystery body".utf8)),
            Message(uid: 3, flags: ["\\Seen"], raw: Array("Message-ID: <s3@x.t>\r\nFrom: alerts@github.com\r\nSubject: PR merged\r\nDate: Fri, 7 Nov 2026 12:00:00 +0000\r\n\r\ncode".utf8)),
        ])])
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "h",
                                     username: "u@t.co", secretRef: "t")
        try? await model.attach(account: account, transport: server)
        return (model, server)
    }

    @Test("CLS-010 Screener 决策流")
    func cls_010_screener_decision_flow() throws {
        let (model, _) = makeModel()
        try model.load(bucket: .screener)
        #expect(model.entries.count == 1)                 // 未知发件人在待定列表
        #expect(model.entries.first?.fromAddress == "stranger@unknown.io")

        let rulesBefore = model.pipeline.rules.count
        try model.decideScreener(stableId: model.entries[0].stableId, to: .feed)
        try model.load(bucket: .feed)
        #expect(model.entries.map(\.fromAddress).contains("stranger@unknown.io")) // 桶已更新
        #expect(model.pipeline.rules.count == rulesBefore + 1)                     // 显式规则生成

        // 下一封同发件人：直接命中规则（不再待定）
        try model.apply([MailEvent(
            stableMessageID: StableMessageID(messageId: "<s4@x.t>", accountFingerprint: "primary"),
            uid: 4, flags: [], raw: Array("Message-ID: <s4@x.t>\r\nFrom: stranger@unknown.io\r\nSubject: again\r\nDate: Fri, 7 Nov 2026 13:00:00 +0000\r\n\r\nx".utf8),
            subject: "again", fromAddress: "stranger@unknown.io")])
        try model.load(bucket: .feed)
        #expect(model.entries.filter { $0.fromAddress == "stranger@unknown.io" }.count == 2)
    }

    @Test("STORE-006 桶计数查询")
    func store_006_bucket_counts() throws {
        let (model, _) = makeModel()
        let counts = model.bucketCounts
        #expect(counts["feed"] == 2)         // netflix + github（种子库均属 feed）
        #expect(counts["screener"] == 1)     // 未知发件人
        #expect(counts["paperTrail"] == nil)
    }

    @Test("JOURNEY-003 邮件详情与未读")
    func journey_003_detail_and_unread() throws {
        let (model, _) = makeModel()
        try model.load(bucket: .feed)
        guard let first = model.entries.first(where: { $0.subject == "S1" }) else {
            Issue.record("S1 not in feed"); return
        }
        let detail = try #require(model.mailDetail(stableId: first.stableId))
        #expect(detail.subject == "S1")
        #expect(detail.textBody == "body one two three")   // 完整正文（非 snippet）
        #expect(detail.isUnread == true)                    // flags 无 \Seen

        let seen = model.entries.first { $0.subject == "PR merged" }
        let seenDetail = try #require(seen.flatMap { model.mailDetail(stableId: $0.stableId) })
        #expect(seenDetail.isUnread == false)
    }
}

// MARK: JOURNEY-004

@MainActor
struct HtmlDetailTests {
    @Test("JOURNEY-004 HTML 邮件详情分离")
    func journey_004_html_detail_separated() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-\(UUID().uuidString)", isDirectory: true)
        let model = MailoAppModel.createLive(storeDirectory: dir)
        let htmlMail = "Message-ID: <h1@x.t>\r\nFrom: news@netflix.com\r\nSubject: HTML\r\nDate: Fri, 7 Nov 2026 15:00:00 +0000\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p><b>New season</b> is out</p>"
        try model.apply([MailEvent(
            stableMessageID: StableMessageID(messageId: "<h1@x.t>", accountFingerprint: "primary"),
            uid: 1, flags: [], raw: Array(htmlMail.utf8),
            subject: "HTML", fromAddress: "news@netflix.com")])
        try model.load(bucket: .feed)
        let entry = try #require(model.entries.first { $0.subject == "HTML" })
        let detail = try #require(model.mailDetail(stableId: entry.stableId))
        #expect(detail.textBody == nil)                    // 无纯文本部分
        #expect(detail.htmlBody?.contains("<b>New season</b>") == true)

        // 沙壳 HTML 构造：CSP 注入（远程图片默认禁）
        let sandboxed = DesignKitTests_sandbox(html: detail.htmlBody ?? "")
        #expect(sandboxed.contains("Content-Security-Policy"))
        #expect(sandboxed.contains("img-src data:"))
    }
}

// 跨 struct 访问 internal 的便捷转发（HtmlMailWebView.sandboxed 为 static）
func DesignKitTests_sandbox(html: String) -> String {
    HtmlMailWebView.sandboxed(html)
}
