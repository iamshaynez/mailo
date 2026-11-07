import Testing
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/SYNC-usecases.md（SYNC-011）

struct SyncRunnerTests {

    @Test("SYNC-011 轮询编排策略（成功复位/失败退避）")
    func sync_011_polling_policy_backoff() throws {
        var policy = PollingPolicy(baseIntervalSec: 30, maxIntervalSec: 300)
        #expect(policy.currentIntervalSec == 30)

        // 连续失败：翻倍至封顶
        policy.onError(); #expect(policy.currentIntervalSec == 60)
        policy.onError(); #expect(policy.currentIntervalSec == 120)
        policy.onError(); #expect(policy.currentIntervalSec == 240)
        policy.onError(); #expect(policy.currentIntervalSec == 300) // 封顶
        policy.onError(); #expect(policy.currentIntervalSec == 300) // 不再涨

        // 恢复成功：立即复位
        policy.onSuccess()
        #expect(policy.currentIntervalSec == 30)

        // SyncRunner 集成：成功轮不退避、快照推进
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 1, raw: Array("Message-ID: <r1@x.t>\r\nFrom: a@b.c\r\nSubject: s\r\n\r\nx".utf8)),
        ])])
        var runner = SyncRunner(accountFingerprint: "acct-9", transport: server)
        let outcome = try runner.runOnce()
        guard case .synced(let events, let snap) = outcome else {
            Issue.record("expected .synced"); return
        }
        #expect(events.count == 1)
        #expect(runner.snapshot?.highestUid == snap.highestUid)
        #expect(runner.policy.currentIntervalSec == 30)
    }
}
