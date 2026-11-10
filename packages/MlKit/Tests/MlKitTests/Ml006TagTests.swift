import Testing
import CoreKit
@testable import MlKit

// MARK: - 用例库：docs/specs/ML-usecases.md（ML-006 组原型向量）

struct Ml006TagTests {

    @Test("ML-006 组原型投票：桶内最近组胜；近平票低置信；无原型 nil")
    func ml_006_tag_prototype_voting() {
        var engine = PrototypeEngine()
        engine.updateTag(bucket: .feed, tag: MailTag("Dev"), embedding: [1, 0, 0])
        engine.updateTag(bucket: .feed, tag: MailTag("Social"), embedding: [0, 1, 0])

        // 一边倒 → 高置信
        let strong = engine.classifyTag(bucket: .feed, embedding: [0.9, 0.1, 0])
        #expect(strong?.tag == MailTag("Dev"))
        #expect(strong!.confidence >= 0.8)

        // 近平票 → 低置信（交 CLS-013 阈值判空）
        let nearTie = engine.classifyTag(bucket: .feed, embedding: [0.55, 0.45, 0])
        #expect(nearTie!.confidence < 0.6)

        // 无组原型 → nil（不猜）
        #expect(engine.classifyTag(bucket: .imbox, embedding: [1, 0, 0]) == nil)

        // 桶内单组无竞争 → 置信 1.0
        var single = PrototypeEngine()
        single.updateTag(bucket: .paperTrail, tag: MailTag("购物"), embedding: [1, 0])
        #expect(single.classifyTag(bucket: .paperTrail, embedding: [0.9, 0.1])?.confidence == 1.0)
    }

    @Test("ML-006 组原型自学习：手动归组即时生效；满窗丢最旧")
    func ml_006_tag_prototype_self_learning() {
        var engine = PrototypeEngine(windowSize: 2)
        engine.updateTag(bucket: .feed, tag: MailTag("Dev"), embedding: [1, 0, 0])

        // 手动归组 Social：新原型加入，后续同向邮件建议 Social
        engine.updateTag(bucket: .feed, tag: MailTag("Social"), embedding: [0, 1, 0])
        #expect(engine.classifyTag(bucket: .feed, embedding: [0, 0.95, 0])?.tag == MailTag("Social"))

        // 满窗滚动：Dev 窗口继续投喂后最旧被丢，方向偏移生效
        engine.updateTag(bucket: .feed, tag: MailTag("Dev"), embedding: [0.2, 0.9, 0])
        engine.updateTag(bucket: .feed, tag: MailTag("Dev"), embedding: [0.2, 0.9, 0])
        let guess = engine.classifyTag(bucket: .feed, embedding: [0.2, 0.9, 0])
        #expect(guess?.tag == MailTag("Dev"))
        #expect(engine.tagPrototypes[.feed]?[MailTag("Dev")]?.count == 2)
    }
}
