import Foundation

/// SELECT 响应的状态提取（MAIL-022）：EXISTS 与 UIDNEXT。
/// 探针/引擎据此构造"最近 N 封"的窄区间 FETCH，避免全量拉取。
public enum SelectState {
    public struct Info: Equatable, Sendable {
        public var exists: Int
        public var uidNext: Int

        public init(exists: Int, uidNext: Int) {
            self.exists = exists
            self.uidNext = uidNext
        }

        /// "最近 count 封"的 UID 区间（uidNext-1 是现存最大 UID 的上界，取 * 开区间兜底删除）。
        public func recentRange(count: Int) -> String {
            let low = max(1, uidNext - max(1, count))
            return "\(low):*"
        }
    }

    /// 从 SELECT 响应字节提取（真实形态：`* 5100 EXISTS`、`* OK [UIDNEXT 51518] ...`，
    /// 方括号在 tokenizer 中保持裸 token——按文本扫描，稳健于 tokenizer 差异）。
    public static func parse(_ bytes: [UInt8]) -> Info {
        let text = String(decoding: bytes, as: UTF8.self)
        var exists = 0, uidNext = 0
        for rawLine in text.components(separatedBy: "\r\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // * n EXISTS
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", let n = Int(parts[1]),
               parts[2].uppercased() == "EXISTS" {
                exists = n
            }
            if let r = line.range(of: "[UIDNEXT "), let end = line.range(of: "]", range: r.upperBound..<line.endIndex) {
                uidNext = Int(line[r.upperBound..<end.lowerBound]) ?? uidNext
            }
        }
        return Info(exists: exists, uidNext: uidNext)
    }
}
