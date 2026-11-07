import Testing
import Foundation
@testable import MirrorKit

// MARK: - 用例库：docs/specs/PERF-usecases.md

struct PerfTests {

    @Test("PERF-001 镜像层批量导入吞吐", .tags(.performance))
    func perf_001_bulk_upsert_throughput() throws {
        let store = try MirrorStore() // 内存库
        let start = Date()
        for i in 0..<1000 {
            let row = MailRow(
                stableId: "<bulk-\(i)@x.t>", account: "perf", folder: "INBOX", uid: i,
                flags: [], subject: "subject \(i) 合同",
                fromAddress: "s\(i)@x.co", snippet: "snippet body \(i)",
                date: "2026-11-07T10:\(String(format: "%02d", i % 60)):\(String(format: "%02d", i % 60))Z")
            try store.upsert(row)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 10, "1000 封 upsert 耗时 \(elapsed)s（含 FTS 触发器）")
    }
}

extension Tag {
    @Tag static var performance: Tag
}
