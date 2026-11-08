import Testing

@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-026 UID STORE 标记写回）

struct Mail026Tests {

    @Test("MAIL-026 UID STORE wire 形态与服务器侧生效")
    func mail_026_uid_store_flags() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 3, raw: Array("Message-ID: <m3@x>\r\nSubject: hi\r\n\r\nbody".utf8)),
        ])])

        // wire 命令合规（tag 由传输层前缀，这里锁 items 形态）
        let cmd = ImapCommand.storeFlags(uid: 3, flags: ["\\Seen"])
        #expect(cmd.wire == "UID STORE 3 +FLAGS.SILENT (\\Seen)")

        // 引擎调用 → 假服务器 flags 更新
        let engine = ImapSyncEngine(accountFingerprint: "primary")
        try engine.storeFlags(uid: 3, flags: ["\\Seen"], transport: server)
        #expect(server.mailboxes["INBOX"]?.messages.first?.flags.contains("\\Seen") == true)

        // 命令确实经传输发出
        guard case .storeFlags = server.sentCommands.last else {
            Issue.record("最后一条命令应为 storeFlags")
            return
        }

        // 不存在的 UID：服务器 NO → 抛错（调用方降级）
        #expect(throws: Error.self) {
            try engine.storeFlags(uid: 99, flags: ["\\Seen"], transport: server)
        }
    }
}
