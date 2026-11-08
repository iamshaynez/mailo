import Testing
import CoreKit
import Foundation
import MailProtoKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-002）

@MainActor
struct Journey002Tests {

    @Test("JOURNEY-002 真实账户装配路径（注入传输）")
    func journey_002_real_account_assembly() throws {
        // 文件库（跨启动持久路径）
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("journey002-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = MailoAppModel.createLive(storeDirectory: dir)

        let account = AccountConfig(displayName: "Outlook", imapHost: "outlook.office365.com",
                                     smtpHost: "smtp.office365.com", username: "me@outlook.com",
                                     secretRef: "test")
        let transport = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 3, messages: [
            Message(uid: 10, raw: Array("Message-ID: <r1@x.t>\r\nFrom: news@netflix.com\r\nSubject: S1\r\nDate: Fri, 6 Nov 2026 10:00:00 +0000\r\n\r\nb".utf8)),
            Message(uid: 11, raw: Array("Message-ID: <r2@x.t>\r\nFrom: pay@stripe.com\r\nSubject: receipt\r\nDate: Fri, 6 Nov 2026 11:00:00 +0000\r\n\r\nb".utf8)),
            Message(uid: 12, raw: Array("Message-ID: <r3@x.t>\r\nFrom: stranger@unknown.io\r\nSubject: hi\r\nDate: Fri, 6 Nov 2026 12:00:00 +0000\r\n\r\nb".utf8)),
        ])])

        let outcome = try await model.attach(account: account, transport: transport)
        guard case .synced(let events, let snap) = outcome else {
            Issue.record("expected .synced"); return
        }
        #expect(events.count == 3)
        #expect(snap.highestUid == 12)
        #expect(model.phase == .connected(email: "me@outlook.com"))

        // 种子名单库分类正确（netflix→feed、stripe→paperTrail）
        try model.load(bucket: .feed)
        #expect(model.entries.map(\.fromAddress) == ["news@netflix.com"])
        try model.load(bucket: .paperTrail)
        #expect(model.entries.map(\.fromAddress) == ["pay@stripe.com"])
        // 未知发件人低置信 → Screener
        #expect(model.screenerCount == 1)

        // 跨启动持久：新模型读同一文件库，冻结分类存活
        let reopened = MailoAppModel.createLive(storeDirectory: dir)
        try reopened.load(bucket: .feed)
        #expect(reopened.entries.count == 1)
    }
}
