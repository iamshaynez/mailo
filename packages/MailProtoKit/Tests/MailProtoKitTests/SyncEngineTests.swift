import Testing
import CoreKit
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md（SYNC-006 ~ 008）

private func mail(_ uid: Int, _ mid: String, from: String = "a@b.co", subject: String? = nil) -> Message {
    Message(uid: uid, raw: Array("Message-ID: \(mid)\r\nFrom: \(from)\r\nSubject: \(subject ?? "s\(mid)")\r\n\r\nbody \(uid)".utf8))
}

struct SyncEngineTests {

    private let fp = "acct-9"

    @Test("SYNC-006 首次全量同步")
    func sync_006_initial_full_sync() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            mail(1, "<m1@x.t>"), mail(2, "<m2@x.t>"), mail(3, "<m3@x.t>"),
        ])])
        let engine = ImapSyncEngine(accountFingerprint: fp)
        let outcome = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)
        guard case .synced(let events, let snap) = outcome else {
            Issue.record("expected .synced, got \(outcome)"); return
        }
        #expect(events.count == 3)
        #expect(events.map(\.uid).sorted() == [1, 2, 3])
        #expect(events.first { $0.uid == 2 }?.subject == "s<m2@x.t>")
        #expect(events.first { $0.uid == 2 }?.raw.contains(Array("body 2".utf8)) == true)
        #expect(snap.uidValidity == 7)
        #expect(snap.highestUid == 3)
    }

    @Test("SYNC-007 增量同步（UID 高水位）")
    func sync_007_incremental_highwater() throws {
        var box = FakeImapServer.Mailbox(uidValidity: 7, messages: [
            mail(1, "<m1@x.t>"), mail(2, "<m2@x.t>"), mail(3, "<m3@x.t>"),
        ])
        let server = FakeImapServer(mailboxes: ["INBOX": box])
        let engine = ImapSyncEngine(accountFingerprint: fp)

        let first = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)
        guard case .synced(_, let snap) = first else {
            Issue.record("first sync failed")
            return
        }

        box.messages.append(mail(4, "<m4@x.t>"))
        server.mailboxes["INBOX"] = box

        let second = try engine.sync(folder: "INBOX", snapshot: snap, transport: server)
        guard case .synced(let events, let snap2) = second else {
            Issue.record("expected .synced, got \(second)"); return
        }
        #expect(events.count == 1)
        #expect(events.first?.uid == 4)
        #expect(snap2.highestUid == 4)
        // 增量只 FETCH 新区间：服务器收到 4:* 的 UID FETCH
        let lastFetch = server.sentCommands.last(where: { if case .fetchUid = $0 { return true }; return false })
        #expect(lastFetch == .fetchUid(range: "4:*", items: "(UID FLAGS BODY[])"))
    }

    @Test("SYNC-008 UIDVALIDITY 重置：重拉全量但分类不丢")
    func sync_008_uidvalidity_reset_keeps_stable_ids() throws {
        let engine = ImapSyncEngine(accountFingerprint: fp)
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            mail(1, "<keep1@x.t>"), mail(2, "<keep2@x.t>"),
        ])])
        let first = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)
        guard case .synced(let beforeEvents, let snap) = first else {
            Issue.record("first sync failed")
            return
        }

        // 服务器重建：UID 全变、原文相同
        server.mailboxes["INBOX"] = .init(uidValidity: 99, messages: [
            mail(101, "<keep1@x.t>"), mail(102, "<keep2@x.t>"),
        ])

        let second = try engine.sync(folder: "INBOX", snapshot: snap, transport: server)
        guard case .resetDetected(let old, let newV, let events, let snap2) = second else {
            Issue.record("expected .resetDetected, got \(second)"); return
        }
        #expect(old == 7 && newV == 99)
        #expect(events.count == 2)
        #expect(snap2.uidValidity == 99)
        // 灵魂断言：稳定主键在重置前后一一相同（分类标注存活）
        let beforeIDs = Set(beforeEvents.map { $0.stableMessageID.value })
        let afterIDs = Set(events.map { $0.stableMessageID.value })
        #expect(beforeIDs == afterIDs)
        #expect(events.map(\.uid).sorted() == [101, 102]) // 但 UID 已更新
    }
}
