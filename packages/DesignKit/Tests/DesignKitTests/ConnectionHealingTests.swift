import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-021 连接自愈）

@MainActor
struct ConnectionHealingTests {

    /// 永远抛 closed 的传输（模拟被服务器踢死的连接）。
    final class DeadTransport: ImapTransport, @unchecked Sendable {
        func send(_ command: ImapCommand) throws -> [UInt8] {
            throw TransportError.closed
        }
    }

    /// 首轮（attach 的 runOnce）健康、其后死亡——点击邮件时撞上死连接的真实形态。
    final class DyingTransport: ImapTransport, @unchecked Sendable {
        let healthy: FakeImapServer
        var alive = true
        init(_ healthy: FakeImapServer) { self.healthy = healthy }
        func send(_ command: ImapCommand) throws -> [UInt8] {
            guard alive else { throw TransportError.closed }
            return try healthy.send(command)
        }
    }

    @Test("JOURNEY-021 正文加载撞死连接：重连一次重试成功，不进 failed 态")
    func journey_021_body_load_reconnects() async throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 6, messages: [
            Message(uid: 4, raw: Array("Message-ID: <h1@x>\r\nFrom: a@h.co\r\nSubject: heal\r\nDate: Sun, 8 Nov 2026 12:00:00 +0000\r\n\r\nhealed body".utf8)),
        ])])
        let dying = DyingTransport(server)
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: dying)

        // 用户点击前连接被踢死
        dying.alive = false

        // 重连句柄：换上健康传输（模拟 refresh + 新连接）
        model.reconnectHandler = { [weak model] in
            guard let model, let r = model.runnerSnapshotForTesting() else { return false }
            var runner = r
            runner.transport = server
            model.swapRunnerForTesting(runner)
            return true
        }

        guard let target = try model.store.search("heal").first?.stableId else {
            Issue.record("目标邮件应已入库")
            return
        }
        let state = await model.loadDetail(stableId: target)

        guard case .loaded(let detail) = state else {
            Issue.record("重连重试后应 loaded：\(state)")
            return
        }
        #expect(detail.textBody?.contains("healed body") == true)

        // 无重连句柄时保持 failed 态（JOURNEY-014 语义不回归）
        let model2 = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        let dying2 = DyingTransport(server)
        try await model2.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: dying2)
        dying2.alive = false // 连接被踢死且无重连句柄
        let target2 = try model2.store.search("heal").first!.stableId
        let state2 = await model2.loadDetail(stableId: target2)
        guard case .failed = state2 else {
            Issue.record("无重连应 failed：\(state2)")
            return
        }
    }

    @Test("JOURNEY-014 BODY 空响应进入可重试失败而非 no body preview")
    func journey_014_empty_body_response_is_failure() async throws {
        final class EmptyBodyTransport: ImapTransport, @unchecked Sendable {
            func send(_ command: ImapCommand) throws -> [UInt8] {
                Array("* 1 FETCH (UID 4 BODY[] NIL)\r\nA1 OK done\r\n".utf8)
            }
        }

        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 6, messages: [
            Message(uid: 4, raw: Array("Message-ID: <empty@x>\r\nFrom: a@h.co\r\nSubject: empty response\r\n\r\nactual body".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)
        guard var runner = model.runnerSnapshotForTesting(), let target = try model.store.search("empty response").first?.stableId else {
            Issue.record("前置邮件应已入库"); return
        }
        runner.transport = EmptyBodyTransport()
        model.swapRunnerForTesting(runner)

        let state = await model.loadDetail(stableId: target)
        guard case .failed = state else {
            Issue.record("空 BODY 应 failed，而非 loaded no body：\(state)")
            return
        }
    }
}
