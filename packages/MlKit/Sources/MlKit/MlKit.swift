import CoreKit
import Foundation

/// 进入模型网关的分类意图输入（发件域 + 主题 + 摘要——两档模型共用）。
public struct MailIntentInput: Hashable, Sendable, Codable {
    public var senderDomain: String
    public var subject: String
    public var snippet: String

    public init(senderDomain: String, subject: String, snippet: String) {
        self.senderDomain = senderDomain.normalized
        self.subject = subject
        self.snippet = snippet
    }
}

/// 模型网关端口：Foundation Models（iOS/macOS 26+，app 层实现）与 Mock/测试实现同口。
/// 输出复用 CoreKit.ModelGuess（bucket + confidence），直接喂 ClassificationPipeline.applyModel。
public protocol MlGateway: Sendable {
    func classify(_ input: MailIntentInput) async throws -> ModelGuess
}

/// embedding 提供者端口（app 层 Core ML 实现；测试用确定性实现）。
public protocol EmbeddingProvider: Sendable {
    func embed(_ text: String) async throws -> [Double]
}

/// 确定性 Mock 网关：查表优先，未命中回退固定猜测（ML-004，golden/CI 的地基）。
public struct MockGateway: MlGateway {
    public var table: [MailIntentInput: ModelGuess]
    public var fallback: ModelGuess

    public init(table: [MailIntentInput: ModelGuess] = [:], fallback: ModelGuess) {
        self.table = table
        self.fallback = fallback
    }

    public func classify(_ input: MailIntentInput) async throws -> ModelGuess {
        return table[input] ?? fallback
    }
}

/// embedding 原型向量引擎（基线 §5 ④：无向量库、余弦 Top-K 投票、原型滚动自学习）。
public struct PrototypeEngine: Sendable, Equatable {
    /// 每桶 K 个原型向量
    public var prototypes: [Bucket: [[Double]]]
    public var windowSize: Int

    public init(prototypes: [Bucket: [[Double]]] = [:], windowSize: Int = 8) {
        self.prototypes = prototypes
        self.windowSize = windowSize
    }

    /// 余弦 Top-1 投票 + 区分度置信度（ML-001/002）。
    /// 置信度 = softmax(余弦相似度) 的 top1 概率：一边倒 → 高；近平票 → 低。
    public func classify(embedding: [Double]) -> ModelGuess {
        var scored: [(bucket: Bucket, cosine: Double)] = []
        for (bucket, vectors) in prototypes {
            let best = vectors.map { Self.cosine($0, embedding) }.max() ?? 0
            scored.append((bucket, best))
        }
        guard let top = scored.max(by: { $0.cosine < $1.cosine }) else {
            return ModelGuess(bucket: .screener, confidence: 0) // 无原型：待定
        }
        // softmax（温度 1）计算 top1 概率作为置信度
        let exps = scored.map { exp($0.cosine) }
        let sum = exps.reduce(0, +)
        let confidence = sum > 0 ? (exp(top.cosine) / sum) : 0
        return ModelGuess(bucket: top.bucket, confidence: confidence)
    }

    /// 原型滚动更新：纠正即时生效（ML-003）。满窗丢最旧。
    public mutating func update(bucket: Bucket, embedding: [Double]) {
        var window = prototypes[bucket] ?? []
        window.append(embedding)
        if window.count > windowSize {
            window.removeFirst(window.count - windowSize)
        }
        prototypes[bucket] = window
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}

// MARK: - Golden 评测（ML-005）

/// 标注样本：输入 + 期望桶。
public struct GoldenCase: Codable, Hashable, Sendable {
    public var input: MailIntentInput
    public var expected: Bucket

    public init(input: MailIntentInput, expected: Bucket) {
        self.input = input
        self.expected = expected
    }
}

/// 分桶统计。
public struct BucketStats: Equatable, Sendable, Codable {
    public var expected: Int
    public var correct: Int

    public init(expected: Int = 0, correct: Int = 0) {
        self.expected = expected
        self.correct = correct
    }
}

/// 评测报告：发版门禁的计算内核。
public struct GoldenReport: Equatable, Sendable {
    public var total: Int
    public var correct: Int
    public var perBucket: [String: BucketStats]

    public var accuracy: Double {
        total == 0 ? 1 : Double(correct) / Double(total)
    }
}

public enum GoldenEvaluator {
    /// JSONL 编解码（一 case 一行，ML-005）。
    public static func encodeJSONL(_ cases: [GoldenCase]) -> String {
        cases.compactMap { c in
            guard let data = try? JSONEncoder().encode(c) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")
    }

    public static func decodeJSONL(_ text: String) -> [GoldenCase] {
        text.split(separator: "\n").compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(GoldenCase.self, from: data)
        }
    }

    /// 评估：网关输出桶 == 期望桶 计正确（ML-005，发版门禁的计算内核）。
    public static func evaluate(_ cases: [GoldenCase], gateway: any MlGateway) async -> GoldenReport {
        var perBucket: [String: BucketStats] = [:]
        var correct = 0
        for c in cases {
            var stats = perBucket[c.expected.rawValue] ?? BucketStats()
            stats.expected += 1
            if let guess = try? await gateway.classify(c.input), guess.bucket == c.expected {
                correct += 1
                stats.correct += 1
            }
            perBucket[c.expected.rawValue] = stats
        }
        return GoldenReport(total: cases.count, correct: correct, perBucket: perBucket)
    }
}
