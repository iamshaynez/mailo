import Testing
import CoreKit
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-003 ~ 007）

struct ImapParserTests {

    @Test("MAIL-003 FETCH 响应解析（ENVELOPE/FLAGS/UID）")
    func mail_003_fetch_envelope_parse() throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 42, flags: ["\\Seen"], raw: Array("Message-ID: <m42@x.test>\r\nFrom: sarah@wave.co\r\nSubject: Re: Contract\r\nDate: Wed, 7 Nov 2026 10:00:00 +0000\r\n\r\nbody".utf8)),
        ])])
        let bytes = try server.send(.fetchUid(range: "1:*", items: "(UID FLAGS INTERNALDATE ENVELOPE)"))
        let lines = try ImapParser.parse(bytes)
        let fetchLine = lines.first { line in
            line.atoms.count >= 2 && line.atoms[0] == .string("*") && line.atoms[1] == .string("42")
        } ?? lines.first { $0.atoms.prefix(2).contains(.string("FETCH")) == false && $0.atoms.contains(.string("FETCH")) }
        #expect(fetchLine != nil, "no FETCH line in: \(lines)")
        guard let data = fetchLine.flatMap({ FetchData.extract(from: $0) }) else {
            Issue.record("FetchData.extract returned nil"); return
        }
        #expect(data.uid == 42)
        #expect(data.flags.contains("\\Seen"))
        #expect(data.subject == "Re: Contract")
        #expect(data.fromAddress == "sarah@wave.co")
    }

    @Test("MAIL-004 字面量跨行续传")
    func mail_004_literal_continuation() throws {
        let header = "Message-ID: <a@b.c>\r\n"
        // 真实 IMAP 形态：{N}\r\n 之后立即跟 N 字节数据，然后才轮到 ')' 收尾
        let wire = "* 1 FETCH (UID 7 BODY[HEADER] {\(header.utf8.count)}\r\n\(header))\r\n"
        let lines = try ImapParser.parse(Array(wire.utf8))
        #expect(lines.count == 1, "字面量与其后的 ')' 属于同一逻辑行，got \(lines)")
        let fetch = lines[0]
        guard case .list(let items) = fetch.atoms[3] else {
            Issue.record("atoms[3] 应为列表: \(fetch)"); return
        }
        #expect(items.contains(.string("UID")))
        #expect(items.contains(.literal(Array(header.utf8))))
    }

    @Test("MAIL-005 RFC2047 encoded-word（含 GBK）")
    func mail_005_encoded_word_gbk() throws {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let gbkBytes = try #require("你好".data(using: gb))
        let gbkWord = "=?GBK?B?\(gbkBytes.base64EncodedString())?="
        #expect(EncodedWord.decode(gbkWord) == "你好")

        #expect(EncodedWord.decode("=?UTF-8?B?5L2g5aW9?=") == "你好")

        // 混排 + 未编码段
        #expect(EncodedWord.decode("Re: =?UTF-8?B?5L2g5aW9?= — 合同") == "Re: 你好 — 合同")

        // 未知编码：原样返回不崩溃
        #expect(EncodedWord.decode("=?X-UNKNOWN?B?Zm9v?=") == "=?X-UNKNOWN?B?Zm9v?=")
    }

    @Test("MAIL-006 UIDVALIDITY 重置检测")
    func mail_006_uidvalidity_reset_event() {
        let prev = MailboxState(folder: "INBOX", uidValidity: 7, exists: 3)
        let same = MailboxState(folder: "INBOX", uidValidity: 7, exists: 5)
        let reset = MailboxState(folder: "INBOX", uidValidity: 99, exists: 1)

        #expect(SyncEvent.diff(previous: prev, current: same) == .mailboxReady(same))
        #expect(SyncEvent.diff(previous: prev, current: reset) == .uidValidityReset(folder: "INBOX", old: 7, new: 99))
        #expect(SyncEvent.diff(previous: nil, current: reset) == .mailboxReady(reset)) // 首次 SELECT 不算重置
    }

    @Test("MAIL-007 能力协商降级")
    func mail_007_capability_negotiation_fallback() {
        #expect(SyncMode.negotiate(capabilities: ["IMAP4rev1", "QRESYNC", "CONDSTORE"]) == .qresync)
        #expect(SyncMode.negotiate(capabilities: ["IMAP4rev1", "CONDSTORE"]) == .condstore)
        #expect(SyncMode.negotiate(capabilities: ["IMAP4rev1"]) == .full)
        #expect(SyncMode.negotiate(capabilities: []) == .full)
    }
}
