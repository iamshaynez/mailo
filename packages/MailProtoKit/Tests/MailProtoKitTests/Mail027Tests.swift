import Testing

@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-027 UID MOVE 删除写回）

struct Mail027Tests {

    @Test("MAIL-027 UID MOVE wire 形态与服务器侧迁移")
    func mail_027_uid_move_to_trash() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 3, flags: ["\\Seen"], raw: Array("Message-ID: <m3@x>\r\nSubject: hi\r\n\r\nbody".utf8)),
        ])])

        // wire 命令合规（tag 由传输层前缀；文件夹名引号风格与 SELECT 一致）
        let cmd = ImapCommand.move(uid: 3, folder: "Trash")
        #expect(cmd.wire == "UID MOVE 3 \"Trash\"")

        // 引擎调用 → 假服务器：INBOX 消失、Trash 出现（flags 保留、新 uid 分配）
        let engine = ImapSyncEngine(accountFingerprint: "primary")
        try engine.move(uid: 3, to: "Trash", transport: server)
        #expect(server.mailboxes["INBOX"]?.messages.isEmpty == true)
        let trashed = try #require(server.mailboxes["Trash"]?.messages.first)
        #expect(trashed.flags.contains("\\Seen"))
        #expect(trashed.uid >= 1)

        // 命令确实经传输发出
        guard case .move = server.sentCommands.last else {
            Issue.record("最后一条命令应为 move")
            return
        }

        // 不存在的 UID：服务器 NO → 抛错（调用方降级，不回滚本地删除）
        #expect(throws: Error.self) {
            try engine.move(uid: 99, to: "Trash", transport: server)
        }
    }
}
