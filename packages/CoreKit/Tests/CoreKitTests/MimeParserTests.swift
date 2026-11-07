import Testing
import Foundation
@testable import CoreKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-008 ~ 012）

struct MimeParserTests {

    @Test("MAIL-008 MIME 头解析（折叠续行/大小写）")
    func mail_008_mime_header_folding() {
        let raw = "MESSAGE-ID: <a@b.c>\r\nSubject: Re:\r\n Contract\r\n redlines\r\nFrom: x@y.z\r\n\r\nbody"
        let email = MimeParser.parse(Array(raw.utf8))
        #expect(email.messageId == "<a@b.c>")
        #expect(email.subject == "Re: Contract redlines")
        #expect(email.from == "x@y.z")
    }

    @Test("MAIL-009 multipart 遍历（含嵌套）")
    func mail_009_multipart_traversal() {
        let raw = """
        Message-ID: <mix@x.test>\r
        From: n@x.co\r
        Subject: mixed\r
        Content-Type: multipart/mixed; boundary="OUT"\r
        \r
        --OUT\r
        Content-Type: multipart/alternative; boundary="IN"\r
        \r
        --IN\r
        Content-Type: text/plain; charset=utf-8\r
        \r
        plain body\r
        --IN\r
        Content-Type: text/html; charset=utf-8\r
        \r
        <p>html body</p>\r
        --IN--\r
        --OUT\r
        Content-Type: application/pdf; name="doc.pdf"\r
        Content-Disposition: attachment; filename="doc.pdf"\r
        Content-Transfer-Encoding: base64\r
        \r
        Zm9v\r
        --OUT--\r
        """
        let email = MimeParser.parse(Array(raw.utf8))
        #expect(email.textBody?.contains("plain body") == true)
        #expect(email.htmlBody?.contains("<p>html body</p>") == true)
        #expect(email.attachments.count == 1, "dump=\(email)")
        #expect(email.attachments.first?.filename == "doc.pdf")
        #expect(email.attachments.first?.body == Array("foo".utf8))
    }

    @Test("MAIL-010 传输编码解码（base64 / quoted-printable）")
    func mail_010_transfer_decoding() {
        // base64: "Hello 中文" 的 base64（UTF-8）
        let b64 = Data("Hello 中文".utf8).base64EncodedString()
        let base64Mail = "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(b64)"
        #expect(MimeParser.parse(Array(base64Mail.utf8)).textBody == "Hello 中文")

        // QP：=XX 与软换行
        let qpMail = "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\ncaf=C3=A9=\r\n latte"
        #expect(MimeParser.parse(Array(qpMail.utf8)).textBody == "café latte")
    }

    @Test("MAIL-011 邮件结构摘要（ParsedEmail）")
    func mail_011_parsed_email_summary() {
        let raw = "From: boss@corp.com\r\nTo: me@x.co\r\nSubject: hi\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\nMessage-ID: <sum@x.test>\r\nContent-Type: text/plain\r\n\r\njust text"
        let email = MimeParser.parse(Array(raw.utf8))
        #expect(email.messageId == "<sum@x.test>")
        #expect(email.subject == "hi")
        #expect(email.from == "boss@corp.com")
        #expect(email.date == "Fri, 7 Nov 2026 10:00:00 +0000")
        #expect(email.textBody == "just text")
        #expect(email.htmlBody == nil)
        #expect(email.attachments.isEmpty)
        #expect(email.headers["to"] == "me@x.co")
    }

    @Test("MAIL-012 正文字符集解码（GBK body）")
    func mail_012_body_charset_gbk() {
        let gb = EncodedWord.gb18030
        let gbkBytes = "你好，附件见下。".data(using: gb)!
        let mail = "Content-Type: text/plain; charset=gbk\r\nContent-Transfer-Encoding: base64\r\n\r\n\(gbkBytes.base64EncodedString())"
        #expect(MimeParser.parse(Array(mail.utf8)).textBody == "你好，附件见下。")

        // charset 缺省：按 UTF-8 容错
        let plain = "Content-Type: text/plain\r\n\r\n纯 UTF-8 正文"
        #expect(MimeParser.parse(Array(plain.utf8)).textBody == "纯 UTF-8 正文")
    }
}
