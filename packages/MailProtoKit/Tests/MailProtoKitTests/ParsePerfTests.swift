import Testing
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/PERF-usecases.md

struct ParsePerfTests {

    @Test("PERF-002 IMAP 解析吞吐", .tags(.performance))
    func perf_002_parse_throughput() throws {
        var wire = ""
        for i in 0..<5000 {
            wire += "* \(i + 1) FETCH (UID \(1000 + i) FLAGS (\\Seen) ENVELOPE (\"Wed, 5 Nov 2026 10:00:00 +0000\" \"Subject line \(i)\" ((NIL NIL \"user\(i)\" \"example.co\")) NIL NIL NIL NIL NIL NIL \"<mid-\(i)@x.t>\"))\r\n"
        }
        wire += "A1 OK FETCH completed\r\n"
        let bytes = Array(wire.utf8)

        let start = Date()
        let lines = try ImapParser.parse(bytes)
        let elapsed = Date().timeIntervalSince(start)

        #expect(lines.count == 5001)
        #expect(elapsed < 5, "5000 行解析耗时 \(elapsed)s")
    }
}

extension Tag {
    @Tag static var performance: Tag
}
