import Testing
import CoreKit
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-013 ~ 015）

struct SmtpAccountTests {

    @Test("MAIL-013 SMTP 会话状态机")
    func mail_013_smtp_session_flow() throws {
        let server = FakeSmtpServer()
        let client = SmtpClient()
        try client.send(from: "me@x.co", to: "you@y.co", subject: "hi", body: "hello",
                        user: "me@x.co", passRef: "k1", transport: server)

        // 命令序列完整且有序
        let stages = server.executedCommands.map { cmd -> String in
            switch cmd {
            case .ehlo: return "EHLO"
            case .authLogin: return "AUTH"
            case .mailFrom: return "MAIL FROM"
            case .rcptTo: return "RCPT TO"
            case .data: return "DATA"
            case .dotData: return "DOT"
            case .quit: return "QUIT"
            }
        }
        #expect(stages == ["EHLO", "AUTH", "MAIL FROM", "RCPT TO", "DATA", "DOT", "QUIT"])

        // 注入 RCPT 失败：中止且不出现 DATA
        let bad = FakeSmtpServer()
        bad.failAt["RCPT TO"] = 550
        #expect(throws: SmtpError.self) {
            try SmtpClient().send(from: "me@x.co", to: "you@y.co", subject: "hi", body: "x",
                                  user: "me", passRef: "k", transport: bad)
        }
        let afterFail = bad.executedCommands.contains { if case .data = $0 { return true }; return false }
        #expect(afterFail == false)
    }

    @Test("MAIL-014 DATA 内容构造与点填充")
    func mail_014_data_dot_stuffing() throws {
        let server = FakeSmtpServer()
        _ = try SmtpClient().send(from: "me@x.co", to: "you@y.co", subject: "dots",
                                  body: "line1\n.hidden line\nline3",
                                  user: "me", passRef: "k", transport: server)
        let block = String(decoding: server.lastDataBlock, as: UTF8.self)
        #expect(block.contains("From: me@x.co"))
        #expect(block.contains("Subject: dots"))
        #expect(block.contains("MIME-Version: 1.0"))
        // 点填充：".hidden" → "..hidden"
        #expect(block.contains("\r\n..hidden line\r\n"))
        #expect(!block.contains("\r\n.hidden line\r\n"))
        // CRLF.CRLF 终止
        #expect(block.hasSuffix(".\r\n"))

        // 往返：接收端（MimeParser）还原正文
        let received = String(decoding: server.lastDataBlock, as: UTF8.self)
            .dropLast(3) // 去 ".\r\n"
        let unStuffed = received.replacingOccurrences(of: "\r\n..", with: "\r\n.")
        let parsed = MimeParser.parse(Array(unStuffed.utf8))
        #expect(parsed.textBody == "line1\r\n.hidden line\r\nline3")
    }

    @Test("MAIL-015 账户配置与指纹")
    func mail_015_account_fingerprint_and_secret_isolation() throws {
        let a = AccountConfig(displayName: "QQ", imapHost: "IMAP.QQ.com", smtpHost: "smtp.qq.com",
                              username: " Me@QQ.com ", secretRef: "k1")
        let b = AccountConfig(displayName: "QQ", imapHost: "imap.qq.com", smtpHost: "SMTP.QQ.COM",
                              username: "me@qq.com", secretRef: "k1")
        let c = AccountConfig(displayName: "163", imapHost: "imap.163.com", smtpHost: "smtp.163.com",
                              username: "me@163.com", secretRef: "k2")

        // 规范化后同账户指纹相同；不同账户不同
        #expect(a.fingerprint == b.fingerprint)
        #expect(a.fingerprint != c.fingerprint)

        // 机密隔离：JSON 编码不含任何凭证明文（结构里根本没有密文字段）
        let json = String(data: try JSONEncoder().encode(a), encoding: .utf8) ?? ""
        #expect(!json.contains("password"))
        #expect(!json.contains("authCode"))
        #expect(json.contains("k1") == false || json.contains("\"secretRef\":\"k1\"")) // 只有引用字段
    }
}
