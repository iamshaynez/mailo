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
    public func classify(embedding: [Double]) -> ModelGuess {
        // PLACEHOLDER (red phase)
        return ModelGuess(bucket: .screener, confidence: 0)
    }

    /// 原型滚动更新：纠正即时生效（ML-003）。
    public mutating func update(bucket: Bucket, embedding: [Double]) {
        // PLACEHOLDER (red phase)
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

/// 评测报告：发版门禁的计算内核。
public struct GoldenReport: Equatable, Sendable {
    public var total: Int
    public var correct: Int
    public var perBucket: [String: (expected: Int, correct: Int)]

    public var accuracy: Double {
        total == 0 ? 1 : Double(correct) / Double(total)
    }
}

public enum GoldenEvaluator {
    /// JSONL 编解码（一 case 一行）。
    public static func encodeJSONL(_ cases: [GoldenCase]) -> String {
        // PLACEHOLDER (red phase)
        return ""
    }

    public static func decodeJSONL(_ text: String) -> [GoldenCase] {
        // PLACEHOLDER (red phase)
        return []
    }

    /// 评估：网关输出桶 == 期望桶 计正确。
    public static func evaluate(_ cases: [GoldenCase], gateway: any MlGateway) async -> GoldenReport {
        // PLACEHOLDER (red phase)
        return GoldenReport(total: 0, correct: 0, perBucket: [:])
    }
}
