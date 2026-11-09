import Testing
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md（SYNC-018 按需历史回填）

@MainActor
struct Sync018Tests {

    private func makeModel(messages: [Int]) async throws -> MailoAppModel {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 3, messages: messages.map { uid in
            Message(uid: uid, raw: Array("Message-ID: <h\(uid)@x>\r\nFrom: news@netflix.com\r\nSubject: h\(uid)\r\n\r\nbody \(uid)".utf8))
        })])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s",
                                    username: "u@t", secretRef: "r")
        try? await model.attach(account: account, transport: server)
        return model
    }

    @Test("SYNC-018 按需回填：水位推进、空批不死循环、到底终止、完成后无操作")
    func sync_018_fetch_more_history() async throws {
        // uid 1 + 连续 300~600：首屏窗口 50 只拉 551~600，其余按需
        let model = try await makeModel(messages: [1] + Array(300...600))

        // 首屏窗口 50（PERF-006）：最早已知 uid = 551，仍有历史
        #expect(model.hasMoreHistory == true)
        #expect(try model.store.oldestUid(folder: "INBOX") == 551)

        // 批 1（100）：区间 451:550 全量命中
        await model.fetchMoreHistory(batchSize: 100)
        #expect(try model.store.oldestUid(folder: "INBOX") == 451)

        // 批 2、批 3（100）：推进到 351 → 300（批 3 区间 251:350 部分命中 uid 300）
        await model.fetchMoreHistory(batchSize: 100)
        #expect(try model.store.oldestUid(folder: "INBOX") == 351)
        await model.fetchMoreHistory(batchSize: 100)
        #expect(try model.store.oldestUid(folder: "INBOX") == 300)

        // 批 4（100）：区间 151:250 全为 UID 空洞 → 无事件但水位推进（不死循环）
        await model.fetchMoreHistory(batchSize: 100)
        #expect(try model.store.oldestUid(folder: "INBOX") == 300, "空批不入库、库内水位不动")
        #expect(model.hasMoreHistory == true, "空批后仍可继续")

        // 批 5（300）：区间 1:150 命中 uid 1 → 到达 UID 1 终止
        await model.fetchMoreHistory(batchSize: 300)
        #expect(try model.store.oldestUid(folder: "INBOX") == 1)
        #expect(model.hasMoreHistory == false, "到达 UID 1 后标记无更多")

        // 到底后调用为无操作（库不再变化）
        let entriesBefore = model.entries.count
        await model.fetchMoreHistory(batchSize: 100)
        #expect(model.entries.count == entriesBefore)
    }

    @Test("SYNC-018 空库/无历史：min(uid)=1 时直接无更多")
    func sync_018_no_more_when_oldest_is_one() async throws {
        let model = try await makeModel(messages: Array(1...3))
        #expect(try model.store.oldestUid(folder: "INBOX") == 1)
        #expect(model.hasMoreHistory == true, "初始乐观，首次拉取时判定")
        await model.fetchMoreHistory(batchSize: 10)
        #expect(model.hasMoreHistory == false, "水位 0：无更早历史")
    }

    // MARK: - SYNC-017（v2：按需批进度）

    /// 慢传输：拉长批窗口，让「进行中」状态可稳定观察（假服务器同步完成太快）。
    final class SlowTransport: ImapTransport, @unchecked Sendable {
        let inner: FakeImapServer
        init(inner: FakeImapServer) { self.inner = inner }
        func send(_ command: ImapCommand) throws -> [UInt8] {
            Thread.sleep(forTimeInterval: 0.15)
            return try inner.send(command)
        }
    }

    @Test("SYNC-017 回填进度：批进行中可见、完成归零（v2 按需）")
    func sync_017_backfill_progress() async throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 3, messages: (1...300).map { uid in
            Message(uid: uid, raw: Array("Message-ID: <p\(uid)@x>\r\nFrom: news@netflix.com\r\nSubject: p\(uid)\r\n\r\nb".utf8))
        })])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)
        #expect(model.backfillProgress == nil, "无回填时无进度")

        // 换慢传输拉长批窗口（150ms > 观察间隔）
        if var r = model.runnerSnapshotForTesting() {
            r.transport = SlowTransport(inner: server)
            model.swapRunnerForTesting(r)
        }

        let task = Task { await model.fetchMoreHistory(batchSize: 100) }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(model.backfillProgress != nil, "批进行中应暴露进度")
        if let p = model.backfillProgress { #expect(p.total >= p.fetched) }
        await task.value
        #expect(model.backfillProgress == nil, "批完成归零")
        #expect(model.backfilledCount > 0, "累计回填数已入库")
    }
}
