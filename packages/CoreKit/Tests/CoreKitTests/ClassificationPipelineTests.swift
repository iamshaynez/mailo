import Testing
@testable import CoreKit

// MARK: - 用例库：docs/specs/CLS-usecases.md

private func signal(
    _ id: String = "<m-\(Int.random(in: 1000...9999))@x.test>",
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

struct ClassificationPipelineTests {

    @Test("CLS-001 用户规则永远赢")
    func cls_001_user_rule_wins_over_roster() {
        let rule = UserRule(matcher: .senderExact("boss@corp.com"), bucket: .feed, ts: 100, deviceId: "A")
        let pipeline = ClassificationPipeline(
            rules: [rule],
            roster: Roster(domainBuckets: ["corp.com": .paperTrail])
        )
        let verdict = pipeline.decide(signal(from: "boss@corp.com"))
        #expect(verdict == .classified(.feed, .userRule(rule.id)))
    }

    @Test("CLS-002 名单库域名命中（大小写不敏感）")
    func cls_002_roster_domain_match_case_insensitive() {
        let pipeline = ClassificationPipeline(roster: Roster(domainBuckets: ["netflix.com": .feed]))
        let verdict = pipeline.decide(signal(from: "no-reply@NETFLIX.com"))
        guard case .classified(.feed, .roster(let key)) = verdict else {
            Issue.record("expected roster hit, got \(verdict)")
            return
        }
        #expect(key == "domain:netflix.com")
    }

    @Test("CLS-003 规则与名单库均未命中 → 交给模型")
    func cls_003_unmatched_goes_to_model() {
        let pipeline = ClassificationPipeline(
            rules: [UserRule(matcher: .senderExact("boss@corp.com"), bucket: .feed, ts: 1, deviceId: "A")],
            roster: Roster(domainBuckets: ["netflix.com": .feed])
        )
        #expect(pipeline.decide(signal(from: "stranger@unknown.org")) == .needsModel)
    }

    @Test("CLS-004 模型低置信 → Screener 待定")
    func cls_004_low_confidence_goes_to_screener() {
        let decision = ClassificationPipeline.applyModel(
            .needsModel,
            guess: ModelGuess(bucket: .feed, confidence: 0.42),
            threshold: 0.60
        )
        #expect(decision == .screener(.belowThreshold(confidence: 0.42)))
    }

    @Test("CLS-005 分类结果冻结（幂等）")
    func cls_005_frozen_result_never_reclassified() {
        let id = StableMessageID(messageId: "<m1@x.test>", accountFingerprint: "acct-9")
        let conflictingRule = UserRule(matcher: .domainExact("x.test"), bucket: .feed, ts: 99, deviceId: "A")
        let pipeline = ClassificationPipeline(rules: [conflictingRule], frozen: [id: .imbox])
        #expect(pipeline.decide(signal("<m1@x.test>", from: "a@x.test")) == .classified(.imbox, .frozen))
    }

    @Test("CLS-006 手动纠正生成显式规则")
    func cls_006_correction_becomes_explicit_rule() {
        let correction = UserRule.correction(senderAddress: "news@indietable.co", bucket: .feed, deviceId: "B", ts: 500)
        let pipeline = ClassificationPipeline(rules: [correction])
        #expect(pipeline.decide(signal(from: "news@indietable.co")) == .classified(.feed, .userRule(correction.id)))
    }

    @Test("CLS-007 匹配优先级：sender > domain > subject")
    func cls_007_matcher_precedence() {
        let senderRule = UserRule(matcher: .senderExact("a@b.c"), bucket: .imbox, ts: 1, deviceId: "A")
        let domainRule = UserRule(matcher: .domainExact("b.c"), bucket: .feed, ts: 2, deviceId: "A")
        let subjectRule = UserRule(matcher: .subjectContains("invoice"), bucket: .paperTrail, ts: 3, deviceId: "A")
        let pipeline = ClassificationPipeline(rules: [subjectRule, domainRule, senderRule]) // 乱序装入
        let verdict = pipeline.decide(signal(from: "a@b.c", subject: "invoice"))
        #expect(verdict == .classified(.imbox, .userRule(senderRule.id)))
    }

    @Test("CLS-008 一端推理、全端共享（管线视角）")
    func cls_008_synced_result_skips_model() {
        let id = StableMessageID(messageId: "<m1@x.test>", accountFingerprint: "acct-9")
        let pipeline = ClassificationPipeline(frozen: [id: .imbox]) // 设备 B 经 SYNC-002 合并得来
        #expect(pipeline.decide(signal("<m1@x.test>", from: "x@y.z")) == .classified(.imbox, .frozen))
    }
}
