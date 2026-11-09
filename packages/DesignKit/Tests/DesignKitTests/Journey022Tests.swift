import Testing
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-022 删除邮件）

@MainActor
struct Journey022Tests {

    @Test("JOURNEY-022 delete：本地删行 + 列表消失 + UID MOVE 写回假服务器")
    func journey_022_delete_moves_to_trash() async throws {
        // 两位陌生发件人各一封 → 均进 Screener（照 JOURNEY-017 装配）
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: [
            Message(uid: 1, raw: Array("Message-ID: <d1@x>\r\nFrom: a@strange.co\r\nSubject: one\r\n\r\nfirst".utf8)),
            Message(uid: 2, raw: Array("Message-ID: <d2@x>\r\nFrom: b@strange.co\r\nSubject: two\r\n\r\nsecond".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(),
                                  pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "t", smtpHost: "t",
                                    username: "u@t", secretRef: "s")
        try await model.attach(account: account, transport: server)
        try model.load(bucket: .screener)
        #expect(model.entries.count == 2)

        // 删除第一封：本地行删除、列表即刻消失、桶计数消减
        let target = try #require(model.entries.first { $0.subject == "one" })
        try model.delete(stableId: target.stableId)
        #expect(try model.store.mail(stableId: target.stableId) == nil)
        #expect(model.entries.map(\.subject) == ["two"])
        #expect(model.bucketCounts[Bucket.screener.rawValue] == 1)

        // 服务器写回路径（独立同步入口，照 storeSeenOnServer 模式）：
        // UID MOVE 到 Trash → INBOX 消失、Trash 出现（flags/正文随迁）
        let remaining = try #require(model.entries.first { $0.subject == "two" })
        try model.moveToTrashOnServer(stableId: remaining.stableId)
        let fake = try #require(model.runnerDebugTransport as? FakeImapServer)
        #expect(fake.mailboxes["INBOX"]?.messages.contains { $0.uid == 2 } != true)
        let trashed = try #require(fake.mailboxes["Trash"]?.messages.first {
            String(decoding: $0.raw, as: UTF8.self).contains("second")
        })
        #expect(trashed.uid >= 1)
        // 删除与写回均为尽力而为：重复调用不崩溃
        try model.moveToTrashOnServer(stableId: "ghost")
    }

    @Test("JOURNEY-022 命令面：delete 可用性与相邻选中回退")
    func journey_022_delete_command_routing() {
        // 可用性与 Reply/Forward 同矩阵：有选中且处于阅读态
        #expect(MailCommandAvailability(selection: nil, isReading: false).canDelete == false)
        #expect(MailCommandAvailability(selection: "x", isReading: true).canDelete == true)

        // 相邻选中回退：删除后 next 优先、末位回退 previous、单封清空（回占位）
        let bridge = MailSelectionBridge(entries: [
            BucketEntry(stableId: "a", bucket: "imbox"),
            BucketEntry(stableId: "b", bucket: "imbox"),
            BucketEntry(stableId: "c", bucket: "imbox"),
        ])
        #expect(bridge.replacement(after: "b") == "c")
        #expect(bridge.replacement(after: "c") == "b")
        #expect(bridge.replacement(after: "a") == "b")
        #expect(bridge.replacement(after: "ghost") == nil)
        let single = MailSelectionBridge(entries: [BucketEntry(stableId: "only", bucket: "imbox")])
        #expect(single.replacement(after: "only") == nil)
    }
}
