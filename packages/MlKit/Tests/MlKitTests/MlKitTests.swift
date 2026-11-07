import Testing
import CoreKit
@testable import MlKit

// MARK: - 用例库：docs/specs/ML-usecases.md（ML-001 ~ 005）

struct MlKitTests {

    @Test("ML-001 原型投票：最近桶胜")
    func ml_001_nearest_prototype_wins() {
        let engine = PrototypeEngine(prototypes: [
            .imbox: [[1, 0, 0]],
            .feed: [[0, 1, 0]],
        ])
        let guess = engine.classify(embedding: [0.2, 0.98, 0.1])
        #expect(guess.bucket == .feed)
        #expect(engine.classify(embedding: [0.95, 0.1, 0]).bucket == .imbox)
    }

    @Test("ML-002 置信度 = 区分度")
    func ml_002_confidence_separation() {
        let engine = PrototypeEngine(prototypes: [
            .imbox: [[1, 0]],
            .feed: [[0, 1]],
        ])
        // 一边倒
        let decisive = engine.classify(embedding: [1, 0.01])
        #expect(decisive.bucket == .imbox)
        #expect(decisive.confidence >= 0.8)
        // 近平票
        let ambiguous = engine.classify(embedding: [1, 0.98])
        #expect(ambiguous.confidence < 0.6) // 管线将判 Screener（CLS-004 阈值 0.60）
    }

    @Test("ML-003 原型自学习（纠正即时生效）")
    func ml_003_prototype_self_learning() {
        var engine = PrototypeEngine(prototypes: [
            .imbox: [[1, 0]],
            .feed: [[0, 1]],
        ])
        let domainVec = [0.9, 0.35] // 原本更靠近 imbox
        #expect(engine.classify(embedding: domainVec).bucket == .imbox)

        engine.update(bucket: .feed, embedding: domainVec) // 用户纠正
        #expect(engine.classify(embedding: domainVec).bucket == .feed)
    }

    @Test("ML-004 Mock 网关确定性")
    func ml_004_mock_gateway_deterministic() async throws {
        let input = MailIntentInput(senderDomain: "netflix.com", subject: "New season", snippet: "watch now")
        let gateway = MockGateway(
            table: [input: ModelGuess(bucket: .feed, confidence: 0.95)],
            fallback: ModelGuess(bucket: .screener, confidence: 0.3))
        let a = try await gateway.classify(input)
        let b = try await gateway.classify(input)
        #expect(a == b)
        #expect(a.bucket == .feed && a.confidence == 0.95)
        // 未命中走 fallback（同样确定）
        let other = try await gateway.classify(MailIntentInput(senderDomain: "x.co", subject: "y", snippet: "z"))
        #expect(other.bucket == .screener)
    }

    @Test("ML-005 golden 评测与 JSONL 往返")
    func ml_005_golden_report_and_jsonl() async throws {
        let cases: [GoldenCase] = [
            GoldenCase(input: MailIntentInput(senderDomain: "netflix.com", subject: "a", snippet: "b"), expected: .feed),
            GoldenCase(input: MailIntentInput(senderDomain: "amzn.com", subject: "receipt", snippet: "order"), expected: .paperTrail),
            GoldenCase(input: MailIntentInput(senderDomain: "friend.co", subject: "hi", snippet: "yo"), expected: .imbox),
        ]
        let jsonl = GoldenEvaluator.encodeJSONL(cases)
        #expect(jsonl.components(separatedBy: "\n").count == 3) // 一 case 一行
        let roundTripped = GoldenEvaluator.decodeJSONL(jsonl)
        #expect(roundTripped == cases)

        // 评估：mock 命中 2/3
        var table: [MailIntentInput: ModelGuess] = [:]
        table[cases[0].input] = ModelGuess(bucket: .feed, confidence: 0.9)
        table[cases[1].input] = ModelGuess(bucket: .feed, confidence: 0.9) // 错分
        table[cases[2].input] = ModelGuess(bucket: .imbox, confidence: 0.9)
        let report = await GoldenEvaluator.evaluate(cases, gateway: MockGateway(table: table, fallback: .init(bucket: .screener, confidence: 0.1)))
        #expect(report.total == 3)
        #expect(report.correct == 2)
        #expect(abs(report.accuracy - 2.0 / 3.0) < 0.0001)
        #expect(report.perBucket["feed"]?.expected == 1)
        #expect(report.perBucket["paperTrail"]?.correct == 0)
    }
}
