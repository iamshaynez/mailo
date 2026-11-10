/// 分类管线（纯函数，基线 v3 §5）：
/// 冻结 > ① 用户规则 > ② 预置名单库 > ③ 模型（管线外回填）> ④ Screener。
/// 组判定（CLS-012/013）独立于桶判定：TagRule 命中 > 模型组建议（阈值内）> 空。
public struct ClassificationPipeline: Hashable, Sendable {
    /// 已按 LWW（SYNC-003）解析出的有效规则集。
    public var rules: [UserRule]
    public var roster: Roster
    /// 冻结表：已定分类的邮件永不重推（CLS-005 / CLS-008）——只锁桶，不锁组。
    public var frozen: [StableMessageID: Bucket]
    /// 组规则集（CLS-012，手动归组生成）。
    public var tagRules: [TagRule]

    public init(rules: [UserRule] = [], roster: Roster = Roster(),
                frozen: [StableMessageID: Bucket] = [:], tagRules: [TagRule] = []) {
        self.rules = rules
        self.roster = roster
        self.frozen = frozen
        self.tagRules = tagRules
    }

    /// 前段：冻结 → 规则（sender>domain>subject，CLS-007）→ 名单库；
    /// 都未命中交给模型（调用方经 MlEngine 端口执行后用 applyModel 回填，CLS-003）。
    public func decide(_ signal: MailSignal) -> PipelineVerdict {
        if let bucket = frozen[signal.messageID] {
            return .classified(bucket, .frozen)
        }
        for rank in 0..<3 {
            if let rule = rules.first(where: { $0.matcher.rank == rank && $0.matcher ~= signal }) {
                return .classified(rule.bucket, .userRule(rule.id))
            }
        }
        if let hit = roster.hit(signal) {
            return .classified(hit.bucket, .roster(hit.key))
        }
        return .needsModel
    }

    /// 后段：前段已定则模型意见不得覆盖；置信度不足 → Screener 待定（CLS-004）。
    public static func applyModel(
        _ verdict: PipelineVerdict,
        guess: ModelGuess,
        threshold: Double = 0.60
    ) -> FinalDecision {
        switch verdict {
        case .classified(let bucket, let reason):
            return .bucket(bucket, reason)
        case .needsModel:
            if guess.confidence >= threshold {
                return .bucket(guess.bucket, .model(confidence: guess.confidence))
            }
            return .screener(.belowThreshold(confidence: guess.confidence))
        }
    }

    /// 组判定的规则段（CLS-012）：TagRule 命中（sender > domain，复用 CLS-007 rank）。
    /// 未命中返回 nil，交模型段（applyTag）裁决；与冻结表无交互。
    public func decideTag(_ signal: MailSignal) -> MailTag? {
        for rank in 0..<3 {
            if let rule = tagRules.first(where: { $0.matcher.rank == rank && $0.matcher ~= signal }) {
                return rule.tag
            }
        }
        return nil
    }

    /// 组判定的模型段（CLS-013）：规则赢；模型组建议按组置信度门槛采纳，
    /// 不足则不分组（宁可不分，不错分）。
    public static func applyTag(
        ruleHit: MailTag?,
        guess: ModelGuess?,
        threshold: Double = 0.60
    ) -> MailTag? {
        if let ruleHit { return ruleHit }
        guard let guess, let tag = guess.tag, guess.tagConfidence >= threshold else { return nil }
        return tag
    }
}
