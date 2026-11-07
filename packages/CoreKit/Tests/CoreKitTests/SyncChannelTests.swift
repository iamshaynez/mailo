import Testing
import Foundation
@testable import CoreKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md（SYNC-005 / 009 / 010）

struct SyncChannelTests {

    @Test("SYNC-005 快照压缩等价")
    func sync_005_snapshot_equivalence() {
        let history: [SyncEntry] = [
            SyncEntry(deviceId: "A", ts: 100, kind: .classification(messageKey: "m1", bucket: .feed)),
            SyncEntry(deviceId: "A", ts: 150, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 150, deviceId: "A"))),
            SyncEntry(deviceId: "B", ts: 200, kind: .classification(messageKey: "m2", bucket: .imbox)),
            SyncEntry(deviceId: "B", ts: 300, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .screener, ts: 300, deviceId: "B"))), // 覆盖 150
        ]
        let tail: [SyncEntry] = [
            SyncEntry(deviceId: "A", ts: 400, kind: .classification(messageKey: "m3", bucket: .paperTrail)),
        ]

        // 全量路径
        let full = EntryMerge.merged(history + tail)

        // 快照路径：前 4 条压缩为快照 + 尾部增量
        let snapshotState = EntryMerge.merged(history)
        let snapshotEntry = SyncEntry(deviceId: "COMPACT", ts: 350,
                                      kind: .snapshot(SyncSnapshotPayload(state: snapshotState)))
        let compacted = EntryMerge.merged([snapshotEntry] + tail)

        #expect(compacted == full)
        // 快照晚于旧写到达不回退：旧 upsert(ts=150) 不应复活被 300 覆盖前的值
        let staleOrder = EntryMerge.merged(tail + [snapshotEntry]
            + [SyncEntry(deviceId: "A", ts: 150, kind: .ruleUpsert(
                UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 150, deviceId: "A")))])
        let key = UserRule(matcher: .senderExact("n@x.co"), bucket: .feed, ts: 0, deviceId: "").matcher.key
        #expect(staleOrder.rules[key]?.bucket == .screener)
    }

    @Test("SYNC-009 写节流（30s / 20 条）")
    func sync_009_flush_throttle() {
        var scheduler = FlushScheduler(maxEntries: 20, maxDelayMs: 30_000)
        let entry = { SyncEntry(deviceId: "A", ts: $0, kind: .ruleTombstone(ruleKey: "k\($0)")) }

        // 19 条：不 flush
        for t in 0..<19 { #expect(scheduler.enqueue(entry(Int64(t))) == false) }
        #expect(scheduler.pending.count == 19)

        // 第 20 条：立即 flush
        #expect(scheduler.enqueue(entry(19)) == true)
        let flushed = scheduler.drain()
        #expect(flushed.count == 20)
        #expect(scheduler.pending.isEmpty)

        // 超时路径：1 条 + 31s 定时器 → flush；未超时（10s）不 flush
        _ = scheduler.enqueue(entry(1000))
        #expect(scheduler.timerFired(now: 1000 + 10_000) == false)
        #expect(scheduler.timerFired(now: 1000 + 31_000) == true)
        #expect(scheduler.drain().count == 1)
    }

    @Test("SYNC-010 wire 编解码往返")
    func sync_010_codec_roundtrip() throws {
        let entries: [SyncEntry] = [
            SyncEntry(id: "e1", deviceId: "A", ts: 100, kind: .classification(messageKey: "m1", bucket: .feed)),
            SyncEntry(id: "e2", deviceId: "B", ts: 200, kind: .ruleUpsert(
                UserRule(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                         matcher: .senderExact("n@x.co"), bucket: .screener, ts: 200, deviceId: "B"))),
        ]
        let wire = SyncCodec.encode(entries)
        let text = String(decoding: wire, as: UTF8.self)
        #expect(text.contains("Message-ID: <mailo-sync-"))   // IMAP 可收纳去重
        #expect(text.contains("X-Mailo-Sync: 1"))            // 识别头

        let decoded = SyncCodec.decode(wire)
        #expect(decoded == entries)

        // 非 sync 邮件安全返回空
        #expect(SyncCodec.decode(Array("From: a@b.c\r\n\r\nplain".utf8)).isEmpty)
    }
}
