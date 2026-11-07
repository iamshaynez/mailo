import Testing
@testable import CoreKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md

struct EntryMergeTests {

    private func classEntry(_ key: String, _ bucket: Bucket, ts: Int64, device: String) -> SyncEntry {
        SyncEntry(deviceId: device, ts: ts, kind: .classification(messageKey: key, bucket: bucket))
    }

    @Test("SYNC-001 合并顺序无关、结果确定")
    func sync_001_merge_is_order_independent() {
        let entries = [
            classEntry("m1", .feed, ts: 1000, device: "A"),
            classEntry("m2", .imbox, ts: 1100, device: "A"),
            SyncEntry(deviceId: "B", ts: 900, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 900, deviceId: "B"))),
            classEntry("m1", .imbox, ts: 1200, device: "B"),
        ]
        let a = EntryMerge.merged(entries)
        let b = EntryMerge.merged(entries.reversed())
        #expect(a == b)
        #expect(a.classifications["m1"]?.bucket == .feed) // first-writer-wins
        #expect(a.classifications["m2"]?.bucket == .imbox)
    }

    @Test("SYNC-002 分类条目 first-writer-wins（ts 相等按 deviceId 决胜）")
    func sync_002_classification_first_writer_wins() {
        // ts 小者胜
        let s1 = EntryMerge.merged([
            classEntry("m1", .feed, ts: 1000, device: "A"),
            classEntry("m1", .imbox, ts: 1200, device: "B"),
        ])
        #expect(s1.classifications["m1"]?.bucket == .feed)

        // ts 相等：deviceId 字典序小者胜（tiebreak 确定）
        let s2 = EntryMerge.merged([
            classEntry("m1", .imbox, ts: 1000, device: "B"),
            classEntry("m1", .feed, ts: 1000, device: "A"),
        ])
        #expect(s2.classifications["m1"]?.bucket == .feed)
        #expect(s2.classifications["m1"]?.deviceId == "A")
    }

    @Test("SYNC-003 规则条目 LWW")
    func sync_003_rule_lww() {
        let key = UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 1000, deviceId: "A").matcher.key
        let state = EntryMerge.merged([
            SyncEntry(deviceId: "A", ts: 1000, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 1000, deviceId: "A"))),
            SyncEntry(deviceId: "B", ts: 1200, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .screener, ts: 1200, deviceId: "B"))),
        ])
        #expect(state.rules[key]?.bucket == .screener)
    }

    @Test("SYNC-004 tombstone 阻止迟到旧写复活")
    func sync_004_tombstone_blocks_stale_upsert() {
        let key = UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 500, deviceId: "A").matcher.key
        let state = EntryMerge.merged([
            SyncEntry(deviceId: "A", ts: 1000, kind: .ruleTombstone(ruleKey: key)),
            SyncEntry(deviceId: "A", ts: 500, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 500, deviceId: "A"))),
        ])
        #expect(state.rules[key] == nil)
        #expect(state.tombstones[key] != nil)
    }
}
