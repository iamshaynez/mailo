import CryptoKit
import Foundation

/// 邮件的稳定关联主键：规范化 Message-ID + 账号指纹。
/// IMAP UID 会因 UIDVALIDITY 重置失稳，永远不得作为关联键（基线 v3 §3）。
public struct StableMessageID: Hashable, Codable, Sendable {
    /// 形如 "<accountFingerprint>|<normalized message id>"
    public let value: String

    public init(messageId: String?, accountFingerprint: String, fallback: FallbackInputs? = nil) {
        let fp = accountFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized = messageId?.normalizedMessageID, !normalized.isEmpty {
            self.value = "\(fp)|\(normalized)"
        } else if let f = fallback {
            self.value = "\(fp)|fb:\(Self.contentDigest(f))"
        } else {
            // 退化：无 Message-ID 也无 fallback 输入。保持确定性（空串），
            // 由调用方契约保证不该走到（MIME 解析层兜底生成 fallback）。
            self.value = "\(fp)|"
        }
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

    private static func contentDigest(_ f: FallbackInputs) -> String {
        let joined = "from|\(f.from)|date|\(f.date)|subject|\(f.subject)"
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var normalizedMessageID: String {
        var s = self
        if s.hasPrefix("<") { s.removeFirst() }
        if s.hasSuffix(">") { s.removeLast() }
        return s.components(separatedBy: .whitespacesAndNewlines).joined().lowercased()
    }
}
