import Testing
import CoreKit
import Foundation
@testable import MirrorKit

// MARK: - 用例库：docs/specs/STORE-usecases.md（STORE-001 ~ 005）

private func row(_ stable: String, uid: Int, subject: String = "s", from: String = "a@b.co",
                 date: String = "2026-11-07T10:00:00Z") -> MailRow {
    MailRow(stableId: stable, account: "acct-9", folder: "INBOX", uid: uid,
            flags: [], subject: subject, fromAddress: from, snippet: "body", date: date)
}

struct MirrorStoreTests {

    @Test("STORE-001 邮件事件 upsert 幂等")
    func store_001_upsert_idempotent() throws {
        let store = try MirrorStore()
        var r = row("<m1@x.t>", uid: 5)
        try store.upsert(r)
        r = MailRow(stableId: "<m1@x.t>", account: "acct-9", folder: "INBOX", uid: 5,
                    flags: ["\\Seen"], subject: "s", fromAddress: "a@b.co", snippet: "body",
                    date: "2026-11-07T10:00:00Z")
        try store.upsert(r)
        let fetched = try store.mail(stableId: "<m1@x.t>")
        #expect(fetched != nil)
        #expect(fetched?.flagList == ["\\Seen"])
        let all = try store.dbQueue.read { db in try MailRow.fetchAll(db) }
        #expect(all.count == 1)
    }

    @Test("STORE-002 bucket 查询按日期倒序")
    func store_002_bucket_query_ordered() throws {
        let store = try MirrorStore()
        try store.upsert(row("<a@x.t>", uid: 1, subject: "older", date: "2026-11-05T10:00:00Z"))
        try store.upsert(row("<b@x.t>", uid: 2, subject: "feed one", date: "2026-11-07T12:00:00Z"))
        try store.upsert(row("<c@x.t>", uid: 3, subject: "newer", date: "2026-11-07T18:00:00Z"))
        try store.freeze(ClassificationRow(stableId: "<a@x.t>", bucket: .imbox, reason: "model"))
        try store.freeze(ClassificationRow(stableId: "<b@x.t>", bucket: .feed, reason: "roster"))
        try store.freeze(ClassificationRow(stableId: "<c@x.t>", bucket: .imbox, reason: "model"))

        let imbox = try store.entries(bucket: .imbox)
        #expect(imbox.count == 2)
        #expect(imbox.map(\.subject) == ["newer", "older"])
    }

    @Test("STORE-003 FTS 中文子串搜索（trigram）")
    func store_003_fts_chinese_substring() throws {
        let store = try MirrorStore()
        try store.upsert(row("<zh@x.t>", uid: 1, subject: "合同修订通知"))
        try store.upsert(row("<en@x.t>", uid: 2, subject: "quarterly report"))

        let hits = try store.search("同修")   // 2 字：LIKE 兜底路径
        #expect(hits.map(\.stableId) == ["<zh@x.t>"])

        let hits3 = try store.search("同修订") // 3 字：trigram 路径
        #expect(hits3.map(\.stableId) == ["<zh@x.t>"])

        let none = try store.search("zebra")
        #expect(none.isEmpty)
    }

    @Test("STORE-004 分类冻结持久化（跨连接）")
    func store_004_classification_persisted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirrorkit-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let store = try MirrorStore(path: dir)
        try store.upsert(row("<p@x.t>", uid: 1))
        try store.freeze(ClassificationRow(stableId: "<p@x.t>", bucket: .paperTrail, reason: "roster"))

        // 模拟重启：新连接读同一文件
        let reopened = try MirrorStore(path: dir)
        let entries = try reopened.entries(bucket: .paperTrail)
        #expect(entries.count == 1)
        #expect(entries.first?.stableId == "<p@x.t>")
    }

    @Test("STORE-005 UIDVALIDITY 重置后的 uid 刷新")
    func store_005_uid_refresh_on_reset() throws {
        let store = try MirrorStore()
        try store.upsert(row("<keep@x.t>", uid: 5))
        try store.freeze(ClassificationRow(stableId: "<keep@x.t>", bucket: .imbox, reason: "userRule"))

        // 服务器重置：同 stableID、新 uid
        try store.upsert(row("<keep@x.t>", uid: 101))

        #expect(try store.mail(stableId: "<keep@x.t>")?.uid == 101)
        let imbox = try store.entries(bucket: .imbox)
        #expect(imbox.count == 1) // 分类标注未丢
        let all = try store.dbQueue.read { db in try MailRow.fetchAll(db) }
        #expect(all.count == 1)
    }
}
