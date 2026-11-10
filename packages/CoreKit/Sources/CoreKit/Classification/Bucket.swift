/// hey 式分类桶（基线 v3 §5）。导航/徽章/归类动画的语义色见 docs/design/design-system.md。
/// `blocked`（CLS-011）：Block 的去处——不出现在任何导航桶，邮件仍留镜像（可搜索/可恢复）。
public enum Bucket: String, Codable, Hashable, Sendable, CaseIterable {
    case imbox
    case feed
    case paperTrail
    case screener
    case setAside
    case blocked

    /// 支持桶内子分组的桶（CLS-012/013 · JOURNEY-026）：Screener 是裁决队列、
    /// Set Aside 是暂存，均无组语义。
    public var isTagNavigable: Bool {
        switch self {
        case .imbox, .feed, .paperTrail: return true
        case .screener, .setAside, .blocked: return false
        }
    }
}
