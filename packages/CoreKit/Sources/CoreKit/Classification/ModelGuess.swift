/// 模型建议（MlEngine 端口的产出形态：Foundation Models / embedding 原型向量共用）。
public struct ModelGuess: Hashable, Sendable {
    public var bucket: Bucket
    public var confidence: Double

    public init(bucket: Bucket, confidence: Double) {
        self.bucket = bucket
        self.confidence = confidence
    }
}
