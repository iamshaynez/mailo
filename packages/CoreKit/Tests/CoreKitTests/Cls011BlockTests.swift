import Testing

@testable import CoreKit

// MARK: - 用例库：docs/specs/CLS-usecases.md（CLS-011 Block 桶语义）

struct Cls011BlockTests {

    @Test("CLS-011 Block 桶：senderExact→blocked 规则直接命中，后续邮件不再打扰")
    func cls_011_block_bucket_semantics() {
        let rule = UserRule.correction(senderAddress: "SPAM@x.co", bucket: .blocked, deviceId: "d", ts: 1)
        let pipeline = ClassificationPipeline(rules: [rule], roster: Roster())

        // 规范化后命中（大写地址写入也匹配）
        let signal = MailSignal(messageID: StableMessageID(messageId: "<m1@x>", accountFingerprint: "primary"),
                                senderLocalPart: "spam", senderDomain: "x.co", subject: "buy now")
        guard case .classified(let bucket, .userRule) = pipeline.decide(signal) else {
            Issue.record("应命中用户规则")
            return
        }
        #expect(bucket == .blocked)
        #expect(Bucket.blocked.rawValue == "blocked")
        #expect(Bucket.allCases.contains(.blocked), "桶枚举全覆盖（解码兼容）")

        // 冻结幂等路径对 blocked 同样成立（CLS-005 语义不因桶而异）
        var frozenPipeline = pipeline
        frozenPipeline.frozen[signal.messageID] = .blocked
        guard case .classified(.blocked, .frozen) = frozenPipeline.decide(signal) else {
            Issue.record("冻结优先于规则")
            return
        }
    }
}
