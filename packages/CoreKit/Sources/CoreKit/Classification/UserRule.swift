import Foundation

/// 用户规则的匹配器。优先级由管线应用顺序决定：sender > domain > subject（CLS-007）。
public enum RuleMatcher: Hashable, Sendable, Codable {
    case senderExact(String)
    case domainExact(String)
    case subjectContains(String)

    /// 规则的唯一归属键（同键规则按 LWW 决胜，SYNC-003）。
    public var key: String {
        switch self {
        case .senderExact(let s): return "sender:\(s.normalized)"
        case .domainExact(let d): return "domain:\(d.normalized)"
        case .subjectContains(let t): return "subject:\(t.normalized)"
        }
    }

    public static func ~= (lhs: RuleMatcher, rhs: MailSignal) -> Bool {
        switch lhs {
        case .senderExact(let s):
            return s.normalized == rhs.senderAddress || s.normalized == rhs.senderLocalPart
        case .domainExact(let d):
            return d.normalized == rhs.senderDomain
        case .subjectContains(let t):
            return rhs.subject.normalized.contains(t.normalized)
        }
    }
}

/// 用户显式规则。手动纠正生成（CLS-006），永不静默学习。
public struct UserRule: Hashable, Sendable, Codable {
    public var id: UUID
    public var matcher: RuleMatcher
    public var bucket: Bucket
    public var ts: Int64
    public var deviceId: String

    public init(id: UUID = UUID(), matcher: RuleMatcher, bucket: Bucket, ts: Int64, deviceId: String) {
        self.id = id
        self.matcher = matcher
        self.bucket = bucket
        self.ts = ts
        self.deviceId = deviceId
    }

    /// 匹配优先级：sender(0) > domain(1) > subject(2)（CLS-007）。
    public var rank: Int {
        switch self {
        case .senderExact: return 0
        case .domainExact: return 1
        case .subjectContains: return 2
        }
    }

    /// 手动纠正：把某发件人的邮件归入某桶 → 生成 senderExact 规则（CLS-006）。
    public static func correction(senderAddress: String, bucket: Bucket, deviceId: String, ts: Int64) -> UserRule {
        UserRule(matcher: .senderExact(senderAddress.normalized), bucket: bucket, ts: ts, deviceId: deviceId)
    }
}
