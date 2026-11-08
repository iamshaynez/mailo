import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-020 时间戳贯穿）

@MainActor
struct TimestampPipelineTests {

    @Test("JOURNEY-020 信封日期入库：ISO 规范化、时间倒序、阅读窗格时间戳可格式化")
    func journey_020_timestamp_pipeline() async throws {
        // 两封不同日期的邮件经 header-first 同步（ENVELOPE 携带 Date 头）
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 6, messages: [
            Message(uid: 1, raw: Array("Message-ID: <t1@x>\r\nFrom: a@old.co\r\nSubject: older\r\nDate: Thu, 5 Nov 2026 09:00:00 +0000\r\n\r\nold".utf8)),
            Message(uid: 2, raw: Array("Message-ID: <t2@x>\r\nFrom: b@new.co\r\nSubject: newer\r\nDate: Sat, 7 Nov 2026 15:30:00 +0000\r\n\r\nnew".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)

        // 信封日期透传入库（不依赖正文回填）
        guard let older = try model.store.mail(stableId: { 
            let rows = try model.store.search("older"); return rows.first?.stableId
        }() ?? "") else {
            Issue.record("older 应已入库")
            return
        }
        #expect(older.date?.isEmpty == false, "date 非空（信封 Date 头透传）")
        #expect(older.date?.hasPrefix("2026-") == true, "ISO8601 规范化（字符串序=时间序）：\(older.date ?? "")")

        // 排序：时间倒序（newer 在前）
        try model.load(bucket: .screener)
        let subjects = model.entries.compactMap(\.subject)
        #expect(subjects.firstIndex(of: "newer")! < subjects.firstIndex(of: "older")!,
                "按收件时间倒序：\(subjects)")

        // 列表时间标签非空（MailDateIndex 双格式解析）
        let index = MailDateIndex(entries: model.entries)
        for entry in model.entries {
            #expect(!index.timeLabel(for: entry.stableId).isEmpty, "\(entry.subject ?? "") 应有时间标签")
        }

        // 阅读窗格时间戳：mailDetail.date → 格式化非空
        let detail = model.mailDetail(stableId: older.stableId)
        #expect(detail?.date?.isEmpty == false)
        let formatted = MailDateGrouping.parse(detail?.date)
            .map { $0.formatted(.dateTime.year().month().day().hour().minute()) } ?? ""
        #expect(!formatted.isEmpty, "阅读窗格时间戳可格式化")

        // 存量 RFC2822 原文兜底解析仍工作（老库数据）；"(UTC)" 注释变体宽容解析
        let legacy = MailDateGrouping.parse("Fri, 7 Nov 2026 10:00:00 +0000")
        #expect(legacy != nil, "RFC2822 存量格式可解析")
        let utcAnnotated = MailDateGrouping.parse("Sat, 07 Nov 2026 10:20:00 +0000 (UTC)")
        #expect(utcAnnotated != nil, "Outlook 式 (UTC) 注释变体可解析")
    }

    @Test("JOURNEY-020 存量日期回填：补 date 不动 flags/raw，完成后代际刷新")
    func journey_020_legacy_date_backfill() async throws {
        // 场景重建：断链时期入库——有 raw/flags、无 date
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 6, messages: [
            Message(uid: 3, flags: ["\\Seen"], raw: Array("Message-ID: <t3@x>\r\nFrom: c@legacy.co\r\nSubject: legacy\r\nDate: Sun, 8 Nov 2026 08:00:00 +0000\r\n\r\nbody".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        // 手工构造"断链存量"行（模拟旧行为：date 空、raw 已回填、已读）
        let legacyRow = MailRow(stableId: "<t3@x>#t", account: "primary", folder: "INBOX", uid: 3,
                                flags: ["\\Seen"], subject: "legacy", fromAddress: "c@legacy.co",
                                snippet: "body", date: nil,
                                raw: Data("Message-ID: <t3@x>\r\nFrom: c@legacy.co\r\nSubject: legacy\r\n\r\nfull body".utf8))
        try model.store.upsert(legacyRow)
        try model.store.freeze(ClassificationRow(stableId: legacyRow.stableId, bucket: .screener, reason: "t"))
        #expect(try model.store.mailsWithoutDate().count == 1)

        // 连接（attach 会触发回填）——等回填任务完成
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)
        for _ in 0..<40 where !(try model.store.mailsWithoutDate().isEmpty) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let fixed = try model.store.mail(stableId: legacyRow.stableId)
        #expect(fixed?.date?.hasPrefix("2026-") == true, "date 已补且 ISO 规范化：\(fixed?.date ?? "")")
        #expect(fixed?.flagList.contains("\\Seen") == true, "flags 未被动")
        #expect(fixed?.raw != nil, "已回填正文未被动")
        #expect(try model.store.mailsWithoutDate().isEmpty)
    }
}


extension TimestampPipelineTests {

    /// 首批 fetchRange 抛错的传输：模拟服务器踢线；重连句柄把它换成健康传输。
    final class FlakyTransport: ImapTransport, @unchecked Sendable {
        let healthy: FakeImapServer
        var failedOnce = false
        init(_ healthy: FakeImapServer) { self.healthy = healthy }
        func send(_ command: ImapCommand) throws -> [UInt8] {
            // 只对「逗号 uid 列表」的回填请求失败一次（attach 首轮 runOnce 是范围请求，不受影响）
            if !failedOnce, case .fetchUid(let range, _) = command, range.contains(",") {
                failedOnce = true
                throw TransportError.closed
            }
            return try healthy.send(command)
        }
    }

    @Test("JOURNEY-020 日期回填被踢线后经 reconnect 续跑完成")
    func journey_020_backfill_reconnects_after_closed() async throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 6, messages: [
            Message(uid: 9, raw: Array("Message-ID: <t9@x>\r\nFrom: f@re.co\r\nSubject: flaky\r\nDate: Sun, 8 Nov 2026 09:00:00 +0000\r\n\r\nb".utf8)),
        ])])
        let flaky = FlakyTransport(server)
        let model = MailoAppModel(store: try MirrorKit.MirrorStore(), pipeline: ClassificationPipeline())
        // 存量无日期行
        try model.store.upsert(MailRow(stableId: "<t9@x>#t", account: "primary", folder: "INBOX", uid: 9,
                                       flags: [], subject: "flaky", fromAddress: "f@re.co",
                                       snippet: "b", date: nil, raw: nil))
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: flaky) // attach 首轮 runOnce 用 flaky（未被置失败，正常）
        // attach 已触发回填：第一批 fetchRange 将抛 closed → 无 reconnect 时会退出
        // 注入重连：换健康传输（模拟 refresh + 新连接）
        model.reconnectHandler = { [weak model] in
            guard let model, let r = model.runnerSnapshotForTesting() else { return false }
            var runner = r
            runner.transport = server
            model.swapRunnerForTesting(runner)
            return true
        }
        model.backfillMissingDates()
        for _ in 0..<60 where !(try model.store.mailsWithoutDate().isEmpty) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(try model.store.mailsWithoutDate().isEmpty, "重连后续跑完成")
        #expect(try model.store.mail(stableId: "<t9@x>#t")?.date?.hasPrefix("2026-") == true)
    }
}
