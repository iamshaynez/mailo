import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（批次 3 反馈与性能）

@MainActor
struct FeedbackPerfTests {

    // MARK: - JOURNEY-014 正文异步加载

    /// 只对 BODY 命令抛错的传输：信封同步正常，正文拉取失败（JOURNEY-014 失败路径）。
    struct BodyThrowingTransport: ImapTransport, Sendable {
        let server: FakeImapServer
        func send(_ command: ImapCommand) throws -> [UInt8] {
            if case .fetchUid(_, let items) = command, items.uppercased().contains("BODY") {
                throw BodyFetchError.boom
            }
            return try server.send(command)
        }
        enum BodyFetchError: Error { case boom }
    }

    private func makeModel(transport: any ImapTransport) async throws -> MailoAppModel {
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s",
                                    username: "u@t", secretRef: "r")
        try await model.attach(account: account, transport: transport)
        return model
    }

    @Test("JOURNEY-014 正文异步加载：loading→loaded（后台回填 raw）；失败给出错误态")
    func journey_014_async_body_load() async throws {
        // 快乐路径：假服务器正文可取
        let ok = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 5, messages: [
            Message(uid: 1, raw: Array("Message-ID: <p1@x>\r\nFrom: a@b.co\r\nSubject: s\r\n\r\nplain body here".utf8)),
        ])])
        let model = try await makeModel(transport: ok)
        try model.load(bucket: .screener)
        let target = try #require(model.entries.first)

        let state = await model.loadDetail(stableId: target.stableId)
        guard case .loaded(let detail) = state else {
            Issue.record("应返回 loaded：\(state)")
            return
        }
        #expect(detail.textBody?.contains("plain body here") == true)
        // raw 已回填持久化（下次打开零网络）
        #expect(try model.store.mail(stableId: target.stableId)?.raw != nil)

        // 失败路径：正文命令抛错 → failed（可重试）
        let failing = BodyThrowingTransport(server: FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 5, messages: [
            Message(uid: 1, raw: Array("Message-ID: <p1@x>\r\nFrom: a@b.co\r\nSubject: s\r\n\r\nplain body here".utf8)),
        ])]))
        let model2 = try await makeModel(transport: failing)
        try model2.load(bucket: .screener)
        let target2 = try #require(model2.entries.first)
        let state2 = await model2.loadDetail(stableId: target2.stableId)
        guard case .failed = state2 else {
            Issue.record("正文拉取失败应进入 failed 态：\(state2)")
            return
        }
    }

    // MARK: - JOURNEY-015 搜索防抖

    @Test("JOURNEY-015 搜索防抖：250ms 内连续输入只执行最后一轮")
    func journey_015_search_debounce() async throws {
        let model = await MailoAppModel.bootstrapDemo()

        model.searchDebounced("ne")
        model.searchDebounced("net")
        model.searchDebounced("netf")
        // 越过防抖窗口（轮询等待：并行测试下 MainActor 调度有抖动）
        for _ in 0..<40 where model.searchExecutions != ["netf"] {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(model.searchExecutions == ["netf"], "只应执行最后一轮：\(model.searchExecutions)")
        #expect(!model.searchResults.isEmpty)

        // 清空（Esc 路径的模型侧）
        model.clearSearch()
        #expect(model.searchResults.isEmpty)
        #expect(model.searchExecutions.last == "", "清空广播空查询恢复列表")
    }

    // MARK: - PERF-004 日期索引零重复解析

    @Test("PERF-004 列表日期索引：一次解析、行标签零重解析、200 行分组亚毫秒均摊")
    func perf_004_row_date_no_formatter() async throws {
        let raw = "Fri, 7 Nov 2026 10:00:00 +0000"
        let entries = (0..<200).map { i in
            BucketEntry(stableId: "m\(i)", subject: "s", fromAddress: "a@b.co", snippet: "x",
                        date: raw, bucket: "imbox", flags: "")
        }

        let index = MailDateIndex(entries: entries)
        #expect(index.date(for: "m0") != nil)
        #expect(index.date(for: "ghost") == nil)

        // 行标签从索引取值：不重复解析（同 raw 日期只解析一次——计数器锁行为）
        let before = MailDateIndex.parseCount
        _ = index.dayLabel(for: "m0")
        _ = index.dayLabel(for: "m1")
        _ = index.timeLabel(for: "m0")
        #expect(MailDateIndex.parseCount == before, "索引内的日期不再触发解析")

        // 200 行分组总耗时（防退化门禁：解析只发生一次）
        let started = Date()
        let grouped = MailDateGrouping.group(entries: entries, index: index)
        let elapsed = Date().timeIntervalSince(started)
        #expect(grouped.first?.entries.count == 200)
        #expect(elapsed < 0.5, "200 行分组应在毫秒级（\(elapsed)s）")
    }

    // SYNC-017 v2（按需批进度）已随 SYNC-018 迁移至 Sync018Tests（startBackfill 移除）。
}
