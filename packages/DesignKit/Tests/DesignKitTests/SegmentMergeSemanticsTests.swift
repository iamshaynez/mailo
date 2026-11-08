import CoreKit
import Foundation
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-018 v2 合并语义）

@MainActor
struct SegmentMergeSemanticsTests {

    private func entry(_ id: String, flags: String = "", date: String = "2026-11-08T10:00:00Z",
                       subject: String? = nil) -> BucketEntry {
        BucketEntry(stableId: id, subject: subject, fromAddress: nil, snippet: nil,
                    date: date, bucket: "imbox", flags: flags)
    }

    @Test("JOURNEY-018 v2 后台刷新合并语义：已读留原位、移桶删除、新未读插入、顺序稳定")
    func journey_018_merge_semantics_grow_only() {
        // 用户快照（New 段）：A 未读在顶部、B 已读但仍在快照（刚读过）
        let snapshot = [
            entry("a", date: "2026-11-08T12:00:00Z"),
            entry("b", flags: "\\Seen", date: "2026-11-08T11:00:00Z"),
            entry("c", date: "2026-11-08T10:00:00Z"),
        ]

        // 后台刷新后的最新桶数据（模拟轮询/回填触发的全量重查）：
        // - a 刚被阅读（flags 已读）——仍在桶里 → 必须留在快照
        // - b 被移出桶（Set Aside/拦截）→ 必须从快照消失
        // - c 不变
        // - d 新到达的未读（更新时间）→ 插入顶部
        let incoming = [
            entry("a", flags: "\\Seen", date: "2026-11-08T12:00:00Z"),
            entry("c", date: "2026-11-08T10:00:00Z"),
            entry("d", date: "2026-11-08T13:00:00Z", subject: "new arrival"),
        ]

        let merged = SegmentSnapshot.merge(segment: 0, snapshot: snapshot, incoming: incoming)

        // 成员：a 留（已读不删）、b 删（移出桶）、c 留、d 增（新未读）
        #expect(merged.map(\.stableId) == ["d", "a", "c"], "实际：\(merged.map(\.stableId))")
        // a 的 flags 已原位合并（未读点/字重变化的数据面）
        #expect(merged.first { $0.stableId == "a" }?.flags.contains("\\Seen") == true)
        // d 插在顶部（date 归位）
        #expect(merged.first?.stableId == "d")
    }

    @Test("JOURNEY-018 v2 Seen 段同样语义；显式重算按最新 flags 全量过滤")
    func journey_018_seen_segment_and_rebuild() {
        let entries = [
            entry("a", flags: "\\Seen"),
            entry("b"),
        ]
        // 显式重算：New 只剩 b、Seen 只剩 a
        #expect(SegmentSnapshot.build(segment: 0, entries: entries).map(\.stableId) == ["b"])
        #expect(SegmentSnapshot.build(segment: 1, entries: entries).map(\.stableId) == ["a"])

        // Seen 段合并：新标读的 c（不在快照、已读）插入
        let snap = SegmentSnapshot.build(segment: 1, entries: entries)
        let merged = SegmentSnapshot.merge(segment: 1, snapshot: snap, incoming: [
            entry("a", flags: "\\Seen"),
            entry("b"),
            entry("c", flags: "\\Seen", date: "2026-11-08T14:00:00Z"),
        ])
        #expect(merged.map(\.stableId).contains("c"))
        // 未读的 b 不属于 Seen 段：既不在快照、也不作为新行插入
        #expect(!merged.map(\.stableId).contains("b"))
    }

    @Test("JOURNEY-018 v2 视图接线：数据刷新走 merge、不消费代际；显式切换走 build")
    func journey_018_view_wiring_source_grep() throws {
        // 源码级锁定接线形态（防止回归到代际重建）：MailListView 不得再消费 entriesGeneration
        let testFile = URL(fileURLWithPath: #filePath)
        let viewPath = testFile.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignKit/MailListView.swift")
        let source = try String(contentsOf: viewPath, encoding: .utf8)
        #expect(!source.contains("entriesGeneration"), "视图不得消费代际（v1 根因）")
        #expect(source.contains("SegmentSnapshot.merge("), "数据刷新必须走 merge 语义")
    }
}
