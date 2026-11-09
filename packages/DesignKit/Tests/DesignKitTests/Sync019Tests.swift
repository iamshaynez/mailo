import Testing
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md（SYNC-019 空闲后台信封回填）

@MainActor
struct Sync019Tests {

    private func makeModel(messageCount: Int) async throws -> MailoAppModel {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 3, messages: (1...messageCount).map { uid in
            Message(uid: uid, raw: Array("Message-ID: <i\(uid)@x>\r\nFrom: news@netflix.com\r\nSubject: i\(uid)\r\n\r\nb".utf8))
        })])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)
        return model
    }

    @Test("SYNC-019 空闲后台回填：逐批推进至拉完，搜索维度全覆盖")
    func sync_019_idle_backfill_completes() async throws {
        // 260 封：首屏窗口 50，剩余 210 由后台循环按批 100 补全（3 批）
        let model = try await makeModel(messageCount: 260)
        #expect(try model.store.oldestUid(folder: "INBOX") == 211, "首屏只有窗口量")

        // 节流常量门禁：后台循环 ≥500ms（Outlook 高频 FETCH 踢线教训）
        #expect(MailoAppModel.idleBackfillPacingNanos >= 500_000_000)

        model.startIdleBackfill()
        // 轮询等待拉完（3 批 × ≥500ms 节流 + 拉取时间；宽超时防 CI 抖动）
        for _ in 0..<100 {
            if !model.hasMoreHistory { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(model.hasMoreHistory == false, "后台循环应拉完全部历史")
        #expect(try model.store.oldestUid(folder: "INBOX") == 1)
        // bucketCounts 无 limit 截断（entries 默认 limit 200 会漏）
        let total = try model.store.bucketCounts().values.reduce(0, +)
        #expect(total == 260, "全部信封入库（正文仍按需，raw 为空）")
    }

    @Test("SYNC-019 断开连接即停：后台循环不再拉取")
    func sync_019_idle_backfill_stops_on_disconnect() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync019-\(UUID().uuidString)", isDirectory: true)
        let model = try await makeModel(messageCount: 260)
        #expect(try model.store.oldestUid(folder: "INBOX") == 211)

        model.startIdleBackfill()
        model.disconnect(vault: nil, directory: dir)
        // 等待超过两个节拍（≥1.2s）：断开后库不再增长
        try await Task.sleep(nanoseconds: 1_200_000_000)
        #expect(try model.store.oldestUid(folder: "INBOX") == 211, "断开后后台循环停止")
    }
}
