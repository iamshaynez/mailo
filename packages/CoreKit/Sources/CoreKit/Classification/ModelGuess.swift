/// 模型建议（MlEngine 端口的产出形态：Foundation Models / embedding 原型向量共用）。
/// 桶建议（bucket+confidence）与组建议（tag+tagConfidence，CLS-013）相互独立：
/// 组置信度由桶内组原型投票单独给出（ML-006），不与桶置信度共用。
public struct ModelGuess: Hashable, Sendable {
    public var bucket: Bucket
    public var confidence: Double
    public var tag: MailTag?
    public var tagConfidence: Double

    public init(bucket: Bucket, confidence: Double, tag: MailTag? = nil, tagConfidence: Double = 0) {
        self.bucket = bucket
        self.confidence = confidence
        self.tag = tag
        self.tagConfidence = tagConfidence
    }
}
