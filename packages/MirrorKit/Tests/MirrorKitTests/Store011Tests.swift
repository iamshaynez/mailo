import Testing
import CoreKit

@testable import MirrorKit

// MARK: - 用例库：docs/specs/STORE-usecases.md（STORE-011 本地删行）

struct Store011Tests {

    @Test("STORE-011 deleteMail：mail/classification 同事务删除、FTS 一致、幂等")
    func store_011_delete_mail() throws {
        let store = try MirrorStore()
        try store.upsert(MailRow(stableId: "m1", account: "primary", folder: "INBOX", uid: 1,
                                 flags: [], subject: "quarterly invoice"))
        try store.upsert(MailRow(stableId: "m2", account: "primary", folder: "INBOX", uid: 2,
                                 flags: [], subject: "keep me"))
        try store.freeze(ClassificationRow(stableId: "m1", bucket: .imbox, reason: "t"))
        try store.freeze(ClassificationRow(stableId: "m2", bucket: .imbox, reason: "t"))
        #expect(try store.entries(bucket: .imbox).count == 2)

        try store.deleteMail(stableId: "m1")

        // mail 行删除
        #expect(try store.mail(stableId: "m1") == nil)
        // classification 行连带删除（查询不再命中）
        #expect(try store.classificationBucket(stableId: "m1") == nil)
        // 桶计数消减
        #expect(try store.bucketCounts()[Bucket.imbox.rawValue] == 1)
        // FTS 触发器自动一致：被删行不再命中，其余行不受影响
        #expect(try store.search("invoice").isEmpty)
        #expect(try store.search("keep").count == 1)

        // 幂等：重复删除 / 不存在的 stableId 静默无操作
        try store.deleteMail(stableId: "m1")
        try store.deleteMail(stableId: "ghost")
        #expect(try store.mail(stableId: "m2") != nil)
    }
}
