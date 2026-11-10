import Testing
import CoreKit
import Foundation

@testable import MirrorKit

// MARK: - 用例库：docs/specs/STORE-usecases.md（STORE-013 v4-tags 迁移与组查询）

private func row(_ id: String, uid: Int, from: String, date: String) -> MailRow {
    MailRow(stableId: id, account: "primary", folder: "INBOX", uid: uid,
            flags: [], subject: "s\(uid)", fromAddress: from, snippet: nil, date: date)
}

struct Store013Tests {

    @Test("STORE-013 v4-tags：tag 落库 / TagFilter 过滤 / tagCounts 排序")
    func store_013_tag_migration_and_queries() throws {
        let store = try MirrorStore()

        try store.upsert(row("<a@x.t>", uid: 1, from: "news@netflix.com", date: "2026-11-07T10:00:00Z"))
        try store.upsert(row("<b@x.t>", uid: 2, from: "alerts@github.com", date: "2026-11-07T11:00:00Z"))
        try store.upsert(row("<c@x.t>", uid: 3, from: "hi@substack.com", date: "2026-11-07T12:00:00Z"))
        try store.upsert(row("<d@x.t>", uid: 4, from: "team@linkedin.com", date: "2026-11-07T13:00:00Z"))

        try store.freeze(ClassificationRow(stableId: "<a@x.t>", bucket: .feed, reason: "roster",
                                           tag: MailTag("Video")))
        try store.freeze(ClassificationRow(stableId: "<b@x.t>", bucket: .feed, reason: "roster",
                                           tag: MailTag("Dev")))
        try store.freeze(ClassificationRow(stableId: "<c@x.t>", bucket: .feed, reason: "roster")) // 无组
        try store.freeze(ClassificationRow(stableId: "<d@x.t>", bucket: .feed, reason: "roster",
                                           tag: MailTag("Dev")))

        // all：整桶（日期倒序保持）
        #expect(try store.entries(bucket: .feed, tag: .all).count == 4)

        // tagged：只看 Dev（2 封），顺序仍按日期倒序
        let dev = try store.entries(bucket: .feed, tag: .tagged(MailTag("Dev")))
        #expect(dev.map(\.stableId) == ["<d@x.t>", "<b@x.t>"])

        // untagged：只看未分组（1 封）
        #expect(try store.entries(bucket: .feed, tag: .untagged).map(\.stableId) == ["<c@x.t>"])

        // tagCounts：组名+计数、按计数倒序、未分组不计入
        #expect(try store.tagCounts(bucket: .feed) == [TagCount(tag: MailTag("Dev"), count: 2),
                                                       TagCount(tag: MailTag("Video"), count: 1)])
        // 空桶 → 空列表
        #expect(try store.tagCounts(bucket: .imbox).isEmpty)
    }

    @Test("STORE-013 setTag：单封幂等；发件人批量；不动桶/冻结")
    func store_013_set_tag_sender_bulk() throws {
        let store = try MirrorStore()
        try store.upsert(row("<n1@x.t>", uid: 1, from: "news@netflix.com", date: "2026-11-07T10:00:00Z"))
        try store.upsert(row("<n2@x.t>", uid: 2, from: "news@netflix.com", date: "2026-11-07T11:00:00Z"))
        try store.upsert(row("<g1@x.t>", uid: 3, from: "alerts@github.com", date: "2026-11-07T12:00:00Z"))
        try store.freeze(ClassificationRow(stableId: "<n1@x.t>", bucket: .feed, reason: "roster"))
        try store.freeze(ClassificationRow(stableId: "<n2@x.t>", bucket: .feed, reason: "roster"))
        try store.freeze(ClassificationRow(stableId: "<g1@x.t>", bucket: .feed, reason: "roster"))

        // 单封改组（幂等）
        try store.setTag(stableId: "<g1@x.t>", tag: MailTag("Dev"))
        try store.setTag(stableId: "<g1@x.t>", tag: MailTag("Dev"))
        #expect(try store.entries(bucket: .feed, tag: .tagged(MailTag("Dev"))).count == 1)

        // 发件人批量：netflix 两封一次归组（CLS-012 即刻生效）
        try store.setTag(senderAddress: "news@netflix.com", bucket: .feed, tag: MailTag("Video"))
        #expect(try store.entries(bucket: .feed, tag: .tagged(MailTag("Video"))).count == 2)
        #expect(try store.tagCounts(bucket: .feed).count == 2)

        // 改组不动 bucket/reason/冻结
        #expect(try store.classificationBucket(stableId: "<n1@x.t>") == .feed)

        // 清组：nil → 未分组
        try store.setTag(senderAddress: "news@netflix.com", bucket: .feed, tag: nil)
        #expect(try store.entries(bucket: .feed, tag: .tagged(MailTag("Video"))).isEmpty)
        #expect(try store.entries(bucket: .feed, tag: .untagged).count == 2)

        // 不存在的邮件：静默无操作
        try store.setTag(stableId: "<none@x.t>", tag: MailTag("X"))
        #expect(try store.tagCounts(bucket: .feed) == [TagCount(tag: MailTag("Dev"), count: 1)])
    }
}
