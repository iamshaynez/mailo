/// hey 式分类桶（基线 v3 §5）。导航/徽章/归类动画的语义色见 docs/design/design-system.md。
public enum Bucket: String, Codable, Hashable, Sendable, CaseIterable {
    case imbox
    case feed
    case paperTrail
    case screener
    case setAside
}
