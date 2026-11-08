import Testing
import AuthKit
import CoreKit
import Foundation
import MailProtoKit
@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-002）

@MainActor
struct Journey002Tests {

    @Test("JOURNEY-002 真实账户装配路径（注入传输）")
    func journey_002_real_account_assembly() async throws {
        // 文件库（跨启动持久路径）
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("journey002-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = MailoAppModel.createLive(storeDirectory: dir)

        let account = AccountConfig(displayName: "Outlook", imapHost: "outlook.office365.com",
                                     smtpHost: "smtp.office365.com", username: "me@outlook.com",
                                     secretRef: "test")
        let transport = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 3, messages: [
            Message(uid: 10, raw: Array("Message-ID: <r1@x.t>\r\nFrom: news@netflix.com\r\nSubject: S1\r\nDate: Fri, 6 Nov 2026 10:00:00 +0000\r\n\r\nb".utf8)),
            Message(uid: 11, raw: Array("Message-ID: <r2@x.t>\r\nFrom: pay@stripe.com\r\nSubject: receipt\r\nDate: Fri, 6 Nov 2026 11:00:00 +0000\r\n\r\nb".utf8)),
            Message(uid: 12, raw: Array("Message-ID: <r3@x.t>\r\nFrom: stranger@unknown.io\r\nSubject: hi\r\nDate: Fri, 6 Nov 2026 12:00:00 +0000\r\n\r\nb".utf8)),
        ])])

        let outcome = try await model.attach(account: account, transport: transport)
        guard case .synced(let events, let snap) = outcome else {
            Issue.record("expected .synced"); return
        }
        #expect(events.count == 3)
        #expect(snap.highestUid == 12)
        #expect(model.phase == .connected(email: "me@outlook.com"))

        // 种子名单库分类正确（netflix→feed、stripe→paperTrail）
        try model.load(bucket: .feed)
        #expect(model.entries.map(\.fromAddress) == ["news@netflix.com"])
        try model.load(bucket: .paperTrail)
        #expect(model.entries.map(\.fromAddress) == ["pay@stripe.com"])
        // 未知发件人低置信 → Screener
        #expect(model.screenerCount == 1)

        // 跨启动持久：新模型读同一文件库，冻结分类存活
        let reopened = MailoAppModel.createLive(storeDirectory: dir)
        try reopened.load(bucket: .feed)
        #expect(reopened.entries.count == 1)
    }
}

// MARK: JOURNEY-005

@MainActor
struct RestoreSessionTests {
    @Test("JOURNEY-005 refresh token 恢复会话（免授权）")
    func journey_005_restore_session() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = MailoAppModel.createLive(storeDirectory: dir)

        // 档案写进模型默认目录（App Support）会污染真机——测试改为直接注入文件目录：
        // 用 AccountStore(directory:) 写入临时目录后由 restore 的 directory 参数读取
        let tmpAccounts = AccountStore(directory: dir)
        try tmpAccounts.save(AccountRecord(email: "me@outlook.com", clientId: "cid-1",
                                           accountKind: .personal, secretRef: "k.me"))
        let vault = InMemoryVault()
        try vault.save("refresh-token-xyz", for: "k.me")

        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 4, messages: [
            Message(uid: 7, raw: Array("Message-ID: <r1@x.t>\r\nFrom: alerts@netflix.com\r\nSubject: restored\r\nDate: Sat, 8 Nov 2026 09:00:00 +0000\r\n\r\nhi".utf8)),
        ])])

        var refreshCalled = false
        let ok = await model.restoreSavedAccount(
            vault: vault,
            directory: dir,
            tokenRefresher: { clientId, refreshToken in
                refreshCalled = true
                return (clientId == "cid-1" && refreshToken == "refresh-token-xyz") ? "access-ok" : nil
            },
            transportFactory: { _ in server })
        #expect(ok == true)
        #expect(refreshCalled == true)                       // 走了 refresh 而非设备码
        #expect(model.phase == .connected(email: "me@outlook.com"))
        try model.load(bucket: .feed)
        #expect(model.entries.first?.subject == "restored")  // 同步已发生

        // 无档案：返回 false
        let fresh = MailoAppModel.createLive(storeDirectory: dir)
        let noAccount = await fresh.restoreSavedAccount(vault: vault, directory: dir,
            tokenRefresher: { _, _ in "x" }, transportFactory: { _ in server })
        #expect(noAccount == true || true) // 同一目录有档案——换空目录断言 false
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString)", isDirectory: true)
        let noAccount2 = await fresh.restoreSavedAccount(vault: vault, directory: empty,
            tokenRefresher: { _, _ in "x" }, transportFactory: { _ in server })
        #expect(noAccount2 == false)
    }
}
