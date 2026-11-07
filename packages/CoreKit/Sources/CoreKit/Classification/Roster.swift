/// 预置名单库：域名/发件人 → 桶（基线 §5 ②）。随 app 版本与静态 CDN 热更。
public struct Roster: Hashable, Sendable {
    public var domainBuckets: [String: Bucket]
    public var senderBuckets: [String: Bucket]

    public init(domainBuckets: [String: Bucket] = [:], senderBuckets: [String: Bucket] = [:]) {
        self.domainBuckets = Dictionary(uniqueKeysWithValues: domainBuckets.map { ($0.key.normalized, $0.value) })
        self.senderBuckets = Dictionary(uniqueKeysWithValues: senderBuckets.map { ($0.key.normalized, $0.value) })
    }

    /// 命中时返回 (命中键, 桶)；sender 优先于 domain。
    public func hit(_ signal: MailSignal) -> (key: String, bucket: Bucket)? {
        if let b = senderBuckets[signal.senderAddress] {
            return ("sender:\(signal.senderAddress)", b)
        }
        if let b = domainBuckets[signal.senderDomain] {
            return ("domain:\(signal.senderDomain)", b)
        }
        return nil
    }
}
