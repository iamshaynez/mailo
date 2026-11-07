import Testing
import CoreKit
import Foundation
@testable import MailProtoKit

/// 假服务器契约：产出可被 ImapParser 消费的真实形态响应（端到端：server → parser）。
struct FakeServerContractTests {

    @Test("CAPABILITY 往返")
    func capability_roundtrip() throws {
        let server = FakeImapServer(capabilities: ["IMAP4rev1", "CONDSTORE"])
        let bytes = try server.send(.capability)
        let lines = try ImapParser.parse(bytes)
        #expect(lines.contains { line in
            line.atoms.count >= 2 && line.atoms[0] == .string("*") && line.atoms[1] == .string("CAPABILITY")
        })
        #expect(server.sentCommands == [.capability])
    }

    @Test("SELECT 返回 EXISTS 与 UIDVALIDITY")
    func select_state() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 1, raw: Array("x: y\r\n\r\nb".utf8)),
            Message(uid: 2, raw: Array("x: y\r\n\r\nb".utf8)),
        ])])
        let lines = try ImapParser.parse(try server.send(.select(folder: "INBOX")))
        let joined = lines.map { "\($0.atoms)" }.joined()
        #expect(joined.contains("2"))
        #expect(joined.contains("7"))
    }

    @Test("GBK 主题的邮件走完整链路（服务器 → 解析器 → 解码）")
    func gbk_subject_end_to_end() throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let subjectBytes = try #require("合同修订".data(using: gb))
        let subjectWord = "=?GBK?B?\(subjectBytes.base64EncodedString())?="
        let raw = "Message-ID: <gbk1@x.test>\r\nFrom: boss@corp.cn\r\nSubject: \(subjectWord)\r\n\r\n正文"
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 9, raw: Array(raw.utf8)),
        ])])
        let lines = try ImapParser.parse(try server.send(.fetchUid(range: "1:*", items: "(UID ENVELOPE)")))
        let fetch = lines.first { $0.atoms.contains(.string("FETCH")) }
        let data = try #require(fetch.flatMap { FetchData.extract(from: $0) })
        #expect(data.subject == "合同修订")
    }
}
