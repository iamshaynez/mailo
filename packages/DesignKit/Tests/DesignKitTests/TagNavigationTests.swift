import Testing
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-026 桶内组导航与手动归组）

@MainActor
struct TagNavigationTests {

    /// 3 封 feed 邮件：netflix ×2（同发件人）+ github ×1；1 封未知发件人（Screener）。
    private func makeModel() async -> MailoAppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tags-\(UUID().uuidString)", isDirectory: true)
        let model = MailoAppModel.createLive(storeDirectory: dir)
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 1, messages: [
            Message(uid: 1, flags: [], raw: Array("Message-ID: <n1@x.t>\r\nFrom: news@netflix.com\r\nSubject: N1\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\n\r\nn1".utf8)),
            Message(uid: 2, flags: [], raw: Array("Message-ID: <n2@x.t>\r\nFrom: news@netflix.com\r\nSubject: N2\r\nDate: Fri, 7 Nov 2026 11:00:00 +0000\r\n\r\nn2".utf8)),
            Message(uid: 3, flags: [], raw: Array("Message-ID: <g1@x.t>\r\nFrom: alerts@github.com\r\nSubject: PR\r\nDate: Fri, 7 Nov 2026 12:00:00 +0000\r\n\r\ncode".utf8)),
        ])])
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "h",
                                     username: "u@t.co", secretRef: "t")
        try? await model.attach(account: account, transport: server)
        return model
    }

    @Test("JOURNEY-026 组导航：点组过滤、未分组、回整桶")
    func journey_026_tag_navigation_filter() async throws {
        let model = await makeModel()

        // 初始全未分组（stableId 取自 attach 后的真实行——fingerprint 为账户哈希）
        try model.load(bucket: .feed)
        #expect(model.entries.count == 3)
        #expect(model.tagCounts[Bucket.feed.rawValue] ?? [] == [])
        let github = try #require(model.entries.first { $0.subject == "PR" })
        let netflix1 = try #require(model.entries.first { $0.subject == "N1" })

        // 手动归组：github → Dev（sender 级）
        try model.assignTag(stableId: github.stableId, tag: MailTag("Dev"))
        // netflix 一封归 Video → 同发件人两封即刻批量归组（CLS-012）
        try model.assignTag(stableId: netflix1.stableId, tag: MailTag("Video"))

        // 组计数：按计数倒序
        #expect(model.tagCounts[Bucket.feed.rawValue] == [TagCount(tag: MailTag("Video"), count: 2),
                                                          TagCount(tag: MailTag("Dev"), count: 1)])

        // 点组 → 列表过滤为 桶+组
        try model.load(bucket: .feed, tag: .tagged(MailTag("Video")))
        #expect(model.tagFilter == .tagged(MailTag("Video")))
        #expect(model.entries.count == 2)
        #expect(model.entries.allSatisfy { $0.fromAddress == "news@netflix.com" })

        // 未分组 → 空
        try model.load(bucket: .feed, tag: .untagged)
        #expect(model.entries.isEmpty)

        // 点桶行 → 回整桶（过滤清除）
        try model.load(bucket: .feed)
        #expect(model.tagFilter == .all)
        #expect(model.entries.count == 3)
    }

    @Test("JOURNEY-026 手动归组：显式 TagRule、LWW 替换、下封直达")
    func journey_026_manual_assign_tag() async throws {
        let model = await makeModel()
        try model.load(bucket: .feed)
        let github = try #require(model.entries.first { $0.subject == "PR" })

        // 归组生成 senderExact→组 显式规则（CLS-012）
        let rulesBefore = model.pipeline.tagRules.count
        try model.assignTag(stableId: github.stableId, tag: MailTag("Dev"))
        #expect(model.pipeline.tagRules.count == rulesBefore + 1)

        // 改组：同发件人规则 LWW 替换，不堆积
        try model.assignTag(stableId: github.stableId, tag: MailTag("Code"))
        #expect(model.pipeline.tagRules.count == rulesBefore + 1)
        #expect(model.pipeline.tagRules.contains { $0.tag == MailTag("Code") })
        #expect(model.tagCounts[Bucket.feed.rawValue] == [TagCount(tag: MailTag("Code"), count: 1)])

        // 下封同发件人新邮件：直接命中规则归组（无需再手动）
        try await model.apply([MailEvent(
            stableMessageID: StableMessageID(messageId: "<g2@x.t>", accountFingerprint: "primary"),
            uid: 4, flags: [], raw: Array("Message-ID: <g2@x.t>\r\nFrom: alerts@github.com\r\nSubject: PR2\r\nDate: Fri, 7 Nov 2026 13:00:00 +0000\r\n\r\ncode".utf8),
            subject: "PR2", fromAddress: "alerts@github.com")])
        try model.load(bucket: .feed, tag: .tagged(MailTag("Code")))
        #expect(model.entries.count == 2)
    }
}
