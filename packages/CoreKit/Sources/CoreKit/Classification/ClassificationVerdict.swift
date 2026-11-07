/// 管线判定原因（可解释、可持久化、可同步）。
public enum ClassificationReason: Hashable, Sendable {
    case userRule(UUID)
    case roster(String)
    case frozen
    case model(confidence: Double)
    case belowThreshold(confidence: Double)
}

/// 管线两段式的前段结论（模型调用发生在管线外，经 MlEngine 端口回填）。
public enum PipelineVerdict: Hashable, Sendable {
    case classified(Bucket, ClassificationReason)
    case needsModel
}

/// 回填模型建议后的最终决策。
public enum FinalDecision: Hashable, Sendable {
    case bucket(Bucket, ClassificationReason)
    case screener(ClassificationReason)
}
