import Foundation

/// 组规则（CLS-012）：手动归组生成的显式规则——CLS-006「手动纠正生成显式规则」
/// 在组维度的镜像。永不静默学习；LWW 可同步（结构对齐 UserRule）。
public struct TagRule: Hashable, Sendable, Codable {
    public var id: UUID
    public var matcher: RuleMatcher
    public var tag: MailTag
    public var ts: Int64
    public var deviceId: String

    public init(id: UUID = UUID(), matcher: RuleMatcher, tag: MailTag, ts: Int64, deviceId: String) {
        self.id = id
        self.matcher = matcher
        self.tag = tag
        self.ts = ts
        self.deviceId = deviceId
    }

    /// 手动归组：某发件人的邮件归入某组 → 生成 senderExact 规则（CLS-012）。
    public static func assignment(senderAddress: String, tag: MailTag, deviceId: String, ts: Int64) -> TagRule {
        TagRule(matcher: .senderExact(senderAddress.normalized), tag: tag, ts: ts, deviceId: deviceId)
    }
}
