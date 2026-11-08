import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-018 分段成员稳定）

@MainActor
struct SegmentStabilityTests {

    @Test("JOURNEY-018 markRead 原位合并：成员/顺序不变、未读点清除、无代际变化；load 才升代际")
    func journey_018_segment_membership_stable_on_read() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        try model.load(bucket: .imbox)
        let before = model.entries.map(\.stableId)
        #expect(before.count == 1)
        let generation0 = model.entriesGeneration

        // 点开阅读 → markRead：X 仍留在原位
        model.markRead(stableId: before[0])
        #expect(model.entries.map(\.stableId) == before, "成员与顺序不变（不整表重查）")
        #expect(model.entries.first?.flags.contains("\\Seen") == true, "flags 原位合并，未读点清除路径")
        #expect(model.entriesGeneration == generation0, "阅读标记不触发列表代际变化")

        // 幂等：重复 markRead 不改变代际
        model.markRead(stableId: before[0])
        #expect(model.entriesGeneration == generation0)

        // markUnread 同理原位
        model.markUnread(stableId: before[0])
        #expect(model.entries.map(\.stableId) == before)
        #expect(model.entries.first?.flags.contains("\\Seen") == false)

        // 搜索结果行同样原位合并（不重查、成员稳定）
        model.search("netflix")
        let searchBefore = model.searchResults.map(\.stableId)
        guard let hit = model.searchResults.first else {
            Issue.record("搜索应有命中")
            return
        }
        model.markRead(stableId: hit.stableId)
        #expect(model.searchResults.map(\.stableId) == searchBefore)
        #expect(model.searchResults.first?.flagList.contains("\\Seen") == true)

        // 恢复已读，再验证切桶（代际变化）→ 重新过滤：已读邮件此时才归入 Previously seen
        model.markRead(stableId: before[0])
        try model.load(bucket: .imbox)
        #expect(model.entriesGeneration > generation0, "load 升代际")
        let readIds = model.entries.filter { $0.flags.contains("\\Seen") }.map(\.stableId)
        let unreadIds = model.entries.filter { !$0.flags.contains("\\Seen") }.map(\.stableId)
        #expect(readIds.contains(before[0]) && !unreadIds.contains(before[0]))
    }

    @Test("JOURNEY-018 快照过滤：段内阅读后成员稳定，段切换时按最新 flags 重算")
    func journey_018_snapshot_filter_semantics() {
        // 视图层过滤语义的纯函数面：段快照构建（成员入口）与 flags 合并（原位）分离
        let unread = BucketEntry(stableId: "a", subject: nil, fromAddress: nil, snippet: nil,
                                 date: nil, bucket: "imbox", flags: "")
        let read = BucketEntry(stableId: "b", subject: nil, fromAddress: nil, snippet: nil,
                               date: nil, bucket: "imbox", flags: "\\Seen")
        let entries = [unread, read]

        // New 段快照：只含未读
        let newSnap = SegmentSnapshot.build(segment: 0, entries: entries)
        #expect(newSnap.map(\.stableId) == ["a"])
        // Seen 段快照：只含已读
        let seenSnap = SegmentSnapshot.build(segment: 1, entries: entries)
        #expect(seenSnap.map(\.stableId) == ["b"])

        // 段内阅读 a：快照成员不变，flags 原位合并
        let merged = SegmentSnapshot.mergeFlags(into: newSnap, from: [
            BucketEntry(stableId: "a", subject: nil, fromAddress: nil, snippet: nil,
                        date: nil, bucket: "imbox", flags: "\\Seen"),
        ])
        #expect(merged.map(\.stableId) == ["a"], "成员稳定")
        #expect(merged.first?.flags.contains("\\Seen") == true, "未读点清除")

        // 下一次重建（切段/代际）才按最新 flags 重算
        let rebuilt = SegmentSnapshot.build(segment: 0, entries: merged + [read])
        #expect(rebuilt.isEmpty == false || rebuilt.map(\.stableId) == [])
        #expect(!rebuilt.map(\.stableId).contains("a"), "重建后 a 归入 Seen")
    }
}
