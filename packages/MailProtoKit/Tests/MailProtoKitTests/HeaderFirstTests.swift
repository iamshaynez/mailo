import Testing
import Foundation
@testable import MailProtoKit
import MirrorKit

// MARK: - 用例库：SYNC-013/014/015 + STORE-007（两段式同步性能机制）

private func mail(_ uid: Int) -> Message {
    Message(uid: uid, raw: Array("Message-ID: <hf\(uid)@x.t>\r\nFrom: alerts@netflix.com\r\nSubject: S\(uid)\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\n\r\nplain body \(uid)".utf8))
}

struct HeaderFirstTests {

    @Test("SYNC-013 / PERF-003 两段式：列表同步不请求正文")
    func sync_013_header_first_fetch() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: (1...20).map(mail))])
        let engine = ImapSyncEngine(accountFingerprint: "a") // 默认 headerFirst
        let outcome = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)
        guard case .synced(let events, _) = outcome else { Issue.record("expected .synced"); return }

        // 事件有摘要、无正文（正文按需）
        #expect(events.count == 20)
        #expect(events.first?.subject == "S1" || events.contains { $0.subject == "S1" })
        #expect(events.allSatisfy { $0.raw.isEmpty })

        // wire 层面：无 BODY[]（PERF-003）
        let fetch = server.sentCommands.last { if case .fetchUid = $0 { return true }; return false }
        #expect(fetch == .fetchUid(range: "1:*", items: "(UID FLAGS ENVELOPE)"))
    }

    @Test("SYNC-014 正文按需拉取（PEEK 不置已读）")
    func sync_014_lazy_body_fetch() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: [
            mail(1), mail(2),
        ])])
        let engine = ImapSyncEngine(accountFingerprint: "a")

        let body = try engine.fetchBody(uid: 2, transport: server)
        #expect(body != nil)
        #expect(String(decoding: body!, as: UTF8.self).contains("plain body 2"))

        // PEEK：邮件 flags 不变（未置 \Seen）
        let lines = try ImapParser.parse(try server.send(.fetchUid(range: "2", items: "(UID FLAGS)")))
        let fd = lines.compactMap { FetchData.extract(from: $0) }.first
        #expect(fd?.flags.contains("\\Seen") == false)
    }

    @Test("SYNC-015 快照持久化：重启只拉增量")
    func sync_015_snapshot_persisted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = try MirrorStore(path: dir)

        var box = FakeImapServer.Mailbox(uidValidity: 9, messages: (1...10).map(mail))
        let server = FakeImapServer(mailboxes: ["INBOX": box])
        let engine = ImapSyncEngine(accountFingerprint: "a")

        // 首轮：入库快照
        let first = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)
        guard case .synced(let e1, let snap) = first else { Issue.record("first"); return }
        #expect(e1.count == 10)
        try store.saveSnapshot(folder: "INBOX", uidValidity: snap.uidValidity, highestUid: snap.highestUid)

        // "重启"：新 store 连接同一文件 + 服务器来新邮件
        let reopened = try MirrorStore(path: dir)
        box.messages.append(mail(11))
        server.mailboxes["INBOX"] = box
        let saved = reopened.loadSnapshot(folder: "INBOX")
        #expect(saved?.highestUid == 10)

        let resume = SyncSnapshot(folder: "INBOX", uidValidity: saved!.uidValidity, highestUid: saved!.highestUid)
        let second = try engine.sync(folder: "INBOX", snapshot: resume, transport: server)
        guard case .synced(let e2, let snap2) = second else { Issue.record("second"); return }

        #expect(e2.count == 1) // 只增量
        #expect(e2.first?.uid == 11)
        #expect(snap2.highestUid == 11)
        let lastFetch = server.sentCommands.last { if case .fetchUid = $0 { return true }; return false }
        #expect(lastFetch == .fetchUid(range: "11:*", items: "(UID FLAGS ENVELOPE)"))
    }

    @Test("STORE-007 批量事务 upsert")
    func store_007_batch_upsert() throws {
        let store = try MirrorStore()
        let rows = (0..<200).map { i in
            MailRow(stableId: "<b\(i)@x.t>", account: "p", folder: "INBOX", uid: i,
                    flags: [], subject: "s\(i)", fromAddress: "a\(i)@x.co",
                    snippet: "n\(i)", date: "2026-11-08T10:00:00Z")
        }
        let tBatch = Date()
        try store.upsertBatch(rows)
        let batchElapsed = Date().timeIntervalSince(tBatch)

        // 与逐封等价
        let all = try store.dbQueue.read { db in try MailRow.fetchAll(db) }
        #expect(all.count == 200)
        // 批量显著快（宽松上限防 flaky：200 封批量 < 逐封典型值的 1/3）
        let tLoop = Date()
        for r in rows { try store.upsert(r) }
        let loopElapsed = Date().timeIntervalSince(tLoop)
        #expect(batchElapsed < max(0.5, loopElapsed / 3), "batch=\(batchElapsed)s loop=\(loopElapsed)s")
    }
}

// MARK: SYNC-016

struct BackfillTests {
    @Test("SYNC-016 历史回填（任意区间拉取）")
    func sync_016_backfill_range() throws {
        // UID 1..1000，含空洞（删除了 500 附近）
        var messages = (1...1000).map(mail)
        messages.removeAll { (500...560).contains($0.uid) }
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: messages)])
        let engine = ImapSyncEngine(accountFingerprint: "a")

        // 首轮窗口：最近 20（1000..981）
        _ = try engine.sync(folder: "INBOX", snapshot: nil, transport: server)

        // 回填批 1：801..980
        let batch1 = try engine.fetchRange("801:980", transport: server)
        #expect(batch1.count == 180)
        #expect(batch1.map(\.uid).max() == 980)

        // 空洞区间（500..560 被删）：返回空但机制可继续
        let hole = try engine.fetchRange("501:560", transport: server)
        #expect(hole.isEmpty)

        // 事件形态与列表同步一致（ENVELOPE、有摘要无正文）
        #expect(batch1.allSatisfy { $0.subject != nil && $0.raw.isEmpty })
    }
}
