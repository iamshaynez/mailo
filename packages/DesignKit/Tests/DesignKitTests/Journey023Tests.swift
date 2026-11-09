import Testing
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-023 正文独立通道）
// MARK: - 用例库：docs/specs/PERF-usecases.md（PERF-006 回填节流与首屏窗口）

/// 命令记录探针（JOURNEY-023）：包装独立假服务器，记录经此通道的命令。
final class TransportProbe: ImapTransport, @unchecked Sendable {
    let inner: FakeImapServer
    private(set) var commands: [ImapCommand] = []
    private let lock = NSLock()

    init(inner: FakeImapServer) { self.inner = inner }

    func send(_ command: ImapCommand) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        commands.append(command)
        return try inner.send(command)
    }
}

@MainActor
struct Journey023Tests {

    @Test("JOURNEY-023 正文加载走独立通道：不占主连接命令锁")
    func journey_023_body_load_uses_dedicated_channel() async throws {
        let raw = Array("Message-ID: <b1@x>\r\nFrom: news@netflix.com\r\nSubject: body here\r\n\r\ntext body".utf8)
        // 主连接（serverA）与独立通道（serverB）各持同一封邮件
        let serverA = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 5, messages: [Message(uid: 1, raw: raw)])])
        let serverB = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 5, messages: [Message(uid: 1, raw: raw)])])
        let probe = TransportProbe(inner: serverB)

        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s",
                                    username: "u@t", secretRef: "r")
        try await model.attach(account: account, transport: serverA)
        model.bodyTransportFactory = { probe }

        // 正文拉取（raw 为空 → fetchBody）：应走 probe 通道
        // （netflix 发件人分类进 feed 桶，attach 默认加载 imbox，故从库内取目标行）
        guard let row = try model.store.mailsWithoutBody().first else {
            Issue.record("应有 1 封无正文邮件"); return
        }
        let state = await model.loadDetail(stableId: row.stableId)
        guard case .loaded(let detail) = state else {
            Issue.record("正文应加载成功：got \(state)"); return
        }
        #expect(detail.textBody == "text body")

        // 通道断言：BODY.PEEK 走 probe，主连接无正文拉取命令
        #expect(probe.commands.contains { cmd in
            if case .fetchUid(_, let items) = cmd { return items.contains("BODY") } else { return false }
        }, "正文拉取应经独立通道")
        let mainBodyFetches = (model.runnerDebugTransport as? FakeImapServer)?.sentCommands.filter { cmd in
            if case .fetchUid(_, let items) = cmd { return items.contains("BODY") } else { return false }
        } ?? []
        #expect(mainBodyFetches.isEmpty, "主连接不应承载正文拉取")

        // 未注入工厂（demo/未配置）：回落主连接路径不回归
        let demo = await MailoAppModel.bootstrapDemo()
        if let first = try demo.store.mailsWithoutBody().first {
            let demoState = await demo.loadDetail(stableId: first.stableId)
            if case .loaded(let d) = demoState { #expect(d.textBody != nil || d.htmlBody != nil) }
        }
    }
}

@MainActor
struct Perf006Tests {

    @Test("PERF-006 回填节流与首屏窗口：常量门禁 + 装配生效")
    func perf_006_pacing_and_window() async throws {
        #expect(MailoAppModel.backfillPacingNanos <= 200_000_000, "回填批间节流 ≤ 200ms")
        #expect(MailoAppModel.syncInitialWindow <= 100, "首屏窗口 ≤ 100 封")

        // 装配生效：runner 引擎窗口即常量（登录首屏拉取量）
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 5, messages: (1...300).map { uid in
            Message(uid: uid, raw: Array("Message-ID: <p\(uid)@x>\r\nFrom: news@netflix.com\r\nSubject: p\(uid)\r\n\r\nb".utf8))
        })])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(
            account: AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s", username: "u@t", secretRef: "r"),
            transport: server)
        let window = model.runnerSnapshotForTesting()?.engine.initialWindow
        #expect(window == MailoAppModel.syncInitialWindow)
        #expect(try model.store.oldestUid(folder: "INBOX") == 300 - MailoAppModel.syncInitialWindow + 1,
                "首屏只拉窗口量（其余留给按需回填）")
    }
}
