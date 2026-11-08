// 经 DesignKit 测试宿主跑真实邮件的 MIME 解析（临时诊断）
import Testing
import CoreKit
@testable import DesignKit

struct MimeProbeTests {
    @Test("真实 Outlook 邮件解析") func probe_real_mail() throws {
        let raw = try String(contentsOfFile: "/tmp/real_mail2.txt", encoding: .utf8)
        // sqlite CAST 会把 BLOB 转 TEXT；Bytes 列可能含非法 UTF-8——用 latin1 容错读
        let bytes = Array(raw.utf8)
        let parsed = MimeParser.parse(bytes)
        print("PROBE subject=\(parsed.subject?.prefix(40) ?? "nil")")
        print("PROBE textBody=\(parsed.textBody?.prefix(80) ?? "nil")")
        print("PROBE htmlBody=\(parsed.htmlBody?.prefix(60) ?? "nil") count=\(parsed.htmlBody?.count ?? 0)")
        print("PROBE attachments=\(parsed.attachments.count)")
        #expect(parsed.textBody != nil || parsed.htmlBody != nil, "至少一种正文")
    }
}
