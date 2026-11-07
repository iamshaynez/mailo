import Foundation

/// 邮件的稳定关联主键：规范化 Message-ID + 账号指纹。
/// IMAP UID 会因 UIDVALIDITY 重置失稳，永远不得作为关联键（基线 v3 §3）。
public struct StableMessageID: Hashable, Codable, Sendable {
    /// 形如 "<accountFingerprint>|<normalized message id>"
    public let value: String

    public init(messageId: String?, accountFingerprint: String, fallback: FallbackInputs? = nil) {
        // PLACEHOLDER (red phase)
        self.value = (messageId ?? "") + accountFingerprint
    }

    /// Message-ID 缺失时的确定性 fallback 输入（MAIL-002）。
    public struct FallbackInputs: Hashable, Sendable {
        public var from: String
        public var date: String
        public var subject: String

        public init(from: String, date: String, subject: String) {
            self.from = from
            self.date = date
            self.subject = subject
        }
    }
}
