import Testing
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-016 ~ 019）

struct ProductionTransportTests {

    @Test("MAIL-016 IMAP 行读取器（分片容错）")
    func mail_016_line_reader_fragmented() {
        let reader = ImapLineReader()
        let header = "Message-ID: <a@b.c>\r\n"
        let full = "* 1 FETCH (UID 7 BODY[] {\(header.count)}\r\n\(header))\r\n" + "* 2 EXISTS\r\nA1 OK done\r\n"

        // 按 3 字节一片喂入（任意切分）
        let bytes = Array(full.utf8)
        var lines: [[UInt8]] = []
        var i = 0
        while i < bytes.count {
            let end = min(i + 3, bytes.count)
            lines += reader.feed(Array(bytes[i..<end]))
            i = end
        }
        #expect(lines.count == 3)
        #expect(String(decoding: lines[0], as: UTF8.self) == "* 1 FETCH (UID 7 BODY[] {\(header.count)}\r\n\(header))")
        #expect(String(decoding: lines[1], as: UTF8.self) == "* 2 EXISTS")
        #expect(String(decoding: lines[2], as: UTF8.self) == "A1 OK done")
    }

    @Test("MAIL-017 XOAUTH2 SASL 载荷构造")
    func mail_017_xoauth2_sasl() {
        let b64 = Sasl.xoauth2(user: "me@x.co", accessToken: "tok123")
        let decoded = String(decoding: Data(base64Encoded: b64) ?? Data(), as: UTF8.self)
        #expect(decoded == "user=me@x.co\u{01}auth=Bearer tok123\u{01}\u{01}")
        #expect(Sasl.emptyResponse == "")
    }

    @Test("MAIL-018 SMTP 多行应答解析")
    func mail_018_smtp_multiline_reply() {
        let reply = SmtpReplyParser.parse(["250-mail.example.com", "250-SIZE 35882577", "250 OK"])
        #expect(reply?.code == 250)
        #expect(reply?.lines.count == 3)
        #expect(reply?.lines.last == "OK")

        // 未出现终行 → nil
        #expect(SmtpReplyParser.parse(["250-a", "250-b"]) == nil)
        // 码不一致 → nil
        #expect(SmtpReplyParser.parse(["250-a", "251 x"]) == nil)
    }

    @Test("MAIL-019 生产传输类型就位（编译级门禁）")
    func mail_019_production_transports_instantiate() throws {
        let imap = TcpImapTransport(host: "imap.example.com", port: 993, connectTimeout: 10)
        let smtp = TcpSmtpTransport(host: "smtp.example.com", port: 465, connectTimeout: 10)

        // 端口符合性（编译期保证 + 运行期冒烟）
        let _: any ImapTransport = imap
        let _: any SmtpTransport = smtp

        // 未连接即发送 → 明确错误（不崩溃）
        #expect(throws: TransportError.self) {
            try imap.send(.capability)
        }
        #expect(throws: TransportError.self) {
            try smtp.execute(.quit)
        }
    }
}
