/// 分类管线（纯函数，基线 v3 §5）：
/// 冻结 > ① 用户规则 > ② 预置名单库 > ③ 模型（管线外回填）> ④ Screener。
public struct ClassificationPipeline: Hashable, Sendable {
    /// 已按 LWW（SYNC-003）解析出的有效规则集。
    public var rules: [UserRule]
    public var roster: Roster
    /// 冻结表：已定分类的邮件永不重推（CLS-005 / CLS-008）。
    public var frozen: [StableMessageID: Bucket]

    public init(rules: [UserRule] = [], roster: Roster = Roster(), frozen: [StableMessageID: Bucket] = [:]) {
        self.rules = rules
        self.roster = roster
        self.frozen = frozen
    }

    /// 前段：冻结 → 规则 → 名单库；都未命中交给模型（调用方执行后经 applyModel 回填）。
    public func decide(_ signal: MailSignal) -> PipelineVerdict {
        // PLACEHOLDER (red phase)
        return .needsModel
    }

    /// 后段：应用模型建议；置信度不足 → Screener 待定（CLS-004）。
    public static func applyModel(
        _ verdict: PipelineVerdict,
        guess: ModelGuess,
        threshold: Double = 0.60
    ) -> FinalDecision {
        // PLACEHOLDER (red phase)
        return .bucket(guess.bucket, .model(confidence: guess.confidence))
    }
}
