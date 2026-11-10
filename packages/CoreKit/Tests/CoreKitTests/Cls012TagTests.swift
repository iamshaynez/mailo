import Testing
@testable import CoreKit

// MARK: - 用例库：docs/specs/CLS-usecases.md（CLS-012/013 桶内子分组）

private func tagSignal(
    _ id: String = "<t-\(Int.random(in: 1000...9999))@x.test>",
    from: String = "someone@example.com",
    subject: String = "Hello"
) -> MailSignal {
    let parts = from.split(separator: "@")
    return MailSignal(
        messageID: StableMessageID(messageId: id, accountFingerprint: "acct-9"),
        senderLocalPart: String(parts[0]),
        senderDomain: String(parts[1]),
        subject: subject
    )
}

struct Cls012TagTests {

    @Test("CLS-012 手动归组生成显式 TagRule：sender 命中、未命中为空")
    func cls_012_manual_tag_rule() {
        let rule = TagRule.assignment(senderAddress: "News@IndieTable.co",
                                      tag: MailTag("Newsletter"), deviceId: "B", ts: 500)
        let pipeline = ClassificationPipeline(tagRules: [rule])

        // 大小写不敏感命中（规范化同 RuleMatcher）
        #expect(pipeline.decideTag(tagSignal(from: "news@indietable.co")) == MailTag("Newsletter"))
        // 未命中 → 无组（交模型，CLS-013）
        #expect(pipeline.decideTag(tagSignal(from: "other@unknown.org")) == nil)
    }

    @Test("CLS-012 组规则优先级 sender > domain；冻结只锁桶不锁组")
    func cls_012_tag_rule_priority_and_freeze() {
        let senderRule = TagRule(matcher: .senderExact("a@b.c"), tag: MailTag("私人"), ts: 1, deviceId: "A")
        let domainRule = TagRule(matcher: .domainExact("b.c"), tag: MailTag("工作"), ts: 2, deviceId: "A")
        let pipeline = ClassificationPipeline(tagRules: [domainRule, senderRule]) // 乱序装入
        #expect(pipeline.decideTag(tagSignal(from: "a@b.c")) == MailTag("私人"))

        // 冻结表锁的是桶；组判定与冻结无交互（冻结邮件仍可被归组）
        let frozenId = StableMessageID(messageId: "<frozen@x.test>", accountFingerprint: "acct-9")
        let frozenPipeline = ClassificationPipeline(
            frozen: [frozenId: .feed],
            tagRules: [TagRule(matcher: .domainExact("x.test"), tag: MailTag("Dev"), ts: 3, deviceId: "A")]
        )
        #expect(frozenPipeline.decideTag(tagSignal("<frozen@x.test>", from: "a@x.test")) == MailTag("Dev"))
        #expect(frozenPipeline.decide(tagSignal("<frozen@x.test>", from: "a@x.test"))
                == .classified(.feed, .frozen)) // 桶判定不受影响
    }

    @Test("CLS-013 模型组建议：规则赢；置信度门槛；无建议为空")
    func cls_013_model_tag_confidence() {
        // 规则命中永远赢
        #expect(ClassificationPipeline.applyTag(
            ruleHit: MailTag("A"),
            guess: ModelGuess(bucket: .feed, confidence: 0.9, tag: MailTag("B"), tagConfidence: 0.99)
        ) == MailTag("A"))

        // 无规则、模型组置信度达标 → 采纳
        #expect(ClassificationPipeline.applyTag(
            ruleHit: nil,
            guess: ModelGuess(bucket: .feed, confidence: 0.9, tag: MailTag("Dev"), tagConfidence: 0.80),
            threshold: 0.60
        ) == MailTag("Dev"))

        // 低置信 → 不分组（宁可不分，不错分）
        #expect(ClassificationPipeline.applyTag(
            ruleHit: nil,
            guess: ModelGuess(bucket: .feed, confidence: 0.9, tag: MailTag("Dev"), tagConfidence: 0.42),
            threshold: 0.60
        ) == nil)

        // 模型无组建议 → 空
        #expect(ClassificationPipeline.applyTag(
            ruleHit: nil,
            guess: ModelGuess(bucket: .feed, confidence: 0.9),
            threshold: 0.60
        ) == nil)

        // 兼容：旧形态 ModelGuess(bucket:confidence:) 不带组
        let legacy = ModelGuess(bucket: .imbox, confidence: 0.9)
        #expect(legacy.tag == nil)
    }
}
