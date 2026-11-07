import Foundation

/// `Mailo/Sync` 条目 ↔ 一封 MIME 邮件字节的编解码（append 进用户邮箱约定文件夹的 wire 形态）。
public enum SyncCodec {
    /// 编码为一封邮件：头带唯一 Message-ID（IMAP 侧天然可去重），body 为 JSON lines。
    public static func encode(_ entries: [SyncEntry]) -> [UInt8] {
        // PLACEHOLDER (red phase)
        return []
    }

    /// 从邮件字节还原条目；非 Mailo/Sync 邮件返回空。
    public static func decode(_ raw: [UInt8]) -> [SyncEntry] {
        // PLACEHOLDER (red phase)
        return []
    }
}
