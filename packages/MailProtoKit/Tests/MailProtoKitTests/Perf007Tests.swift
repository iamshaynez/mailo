import Testing
import Foundation

@testable import MailProtoKit

// MARK: - 用例库：docs/specs/PERF-usecases.md（PERF-007 行读取器大响应吞吐）

struct Perf007Tests {

    @Test("PERF-007 行读取器 4MB：扫描量线性界 + 行为不变")
    func perf_007_line_reader_throughput() throws {
        // ~4MB 响应：4000 行，每 10 行夹一个 2KB 字面量（ENVELOPE 批 + BODY 混合形态）。
        // 门禁用结构性指标（PERF-004 计数器模式）：scannedBytes ≤ 输入 3 倍——
        // 无边界记忆/头部移位的实现随分片喂入反复重扫尾部（百 MB 级），Debug/CI 波动不影响判定。
        var bytes: [UInt8] = []
        var expectedLines = 0
        for i in 1...4000 {
            if i % 10 == 0 {
                bytes += Array("* \(i) FETCH (UID \(i) BODY[] {2048}\r\n".utf8)
                bytes += Array(repeating: UInt8(ascii: "x"), count: 2048)
                bytes += Array(")\r\n".utf8)
            } else {
                let filler = String(repeating: "f", count: 900)
                bytes += Array("* \(i) FETCH (UID \(i) ENVELOPE (\"\(filler)\"))\r\n".utf8)
            }
            expectedLines += 1
        }
        #expect(bytes.count > 4_000_000, "样本应达 4MB 级（实际 \(bytes.count)B）")

        // 16KB 分片喂入（模拟 NWConnection 段到达）
        let reader = ImapLineReader()
        let started = Date()
        var lines = 0
        var idx = 0
        while idx < bytes.count {
            let end = min(idx + 16384, bytes.count)
            lines += reader.feed(Array(bytes[idx..<end])).count
            idx = end
        }
        let elapsed = Date().timeIntervalSince(started)

        #expect(lines == expectedLines, "逻辑行数（字面量行整体计 1 行）")
        print("scanned=\(reader.scannedBytes) bytes=\(bytes.count)\n"); #expect(reader.scannedBytes <= bytes.count * 3,
                "扫描量应线性（实际 \(reader.scannedBytes)B vs 输入 \(bytes.count)B）")
        #expect(elapsed < 1.0, "4MB 提取粗上限 1s（实际 \(elapsed)s）")
    }
}
