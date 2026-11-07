/// 进入分类管线的邮件信号（v1：规则/名单库所需的最小字段）。
public struct MailSignal: Hashable, Sendable {
    public var messageID: StableMessageID
    public var senderLocalPart: String
    public var senderDomain: String
    public var subject: String

    public init(messageID: StableMessageID, senderLocalPart: String, senderDomain: String, subject: String) {
        self.messageID = messageID
        self.senderLocalPart = senderLocalPart.normalized
        self.senderDomain = senderDomain.normalized
        self.subject = subject
    }

    public var senderAddress: String { "\(senderLocalPart)@\(senderDomain)" }
}

extension String {
    /// 规则/名单库匹配统一规范化：小写 + 去首尾空白。
    public var normalized: String { lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
}
