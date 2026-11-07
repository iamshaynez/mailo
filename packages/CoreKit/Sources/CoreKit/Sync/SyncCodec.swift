import Foundation

/// `Mailo/Sync` 条目 ↔ 一封 MIME 邮件字节的编解码（append 进用户邮箱约定文件夹的 wire 形态）。
public enum SyncCodec {
    /// 编码为一封邮件：头带唯一 Message-ID（IMAP 侧天然可去重），body 为 JSON lines（SYNC-010）。
    public static func encode(_ entries: [SyncEntry]) -> [UInt8] {
        let lines = entries
            .compactMap { entry -> String? in
                guard let data = try? JSONEncoder().encode(entry) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            .joined(separator: "\n")
        let head = """
        Message-ID: <mailo-sync-\(UUID().uuidString)@sync.mailo.local>\r
        X-Mailo-Sync: 1\r
        Content-Type: application/json; charset=utf-8\r
        Content-Transfer-Encoding: 8bit\r

        """
        return Array((head + lines + "\r\n").utf8)
    }

    /// 从邮件字节还原条目；非 Mailo/Sync 邮件（无识别头）返回空（SYNC-010）。
    public static func decode(_ raw: [UInt8]) -> [SyncEntry] {
        let text = String(decoding: raw, as: UTF8.self)
        guard text.contains("X-Mailo-Sync:") else { return [] }
        guard let bodyStart = text.range(of: "\r\n\r\n") else { return [] }
        let body = String(text[bodyStart.upperBound...])
        return body.split(separator: "\n").compactMap { line in
            guard let data = String(line).trimmingCharacters(in: .whitespaces).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SyncEntry.self, from: data)
        }
    }
}
