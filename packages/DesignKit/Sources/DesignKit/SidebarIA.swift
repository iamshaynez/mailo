import CoreKit
import Foundation

/// 侧栏信息架构 v2 的纯模型（JOURNEY-025）：构成唯一权威，视图零分叉。
/// HEY 方法论导航：Screener 置顶（门卫）→ Imbox/Feed/Paper Trail（三桶，可展开组）→
/// Set Aside；底部动作组。零假项——每一项都对应真实动作或真实计数。
public enum SidebarIA {

    /// 侧栏条目（可执行导航的最小描述；计数来自 bucketCounts）。
    public enum Entry: Equatable, Hashable, Sendable {
        /// 桶导航：count 为真实桶计数；expandable = 桶支持桶内组列表（JOURNEY-026）。
        case bucket(Bucket, count: Int, expandable: Bool)
        case separator
        case compose(enabled: Bool)
        case settings
        case syncNow(enabled: Bool)
        case exitDemo
    }

    /// 侧栏构成（JOURNEY-025）：顺序 Screener → sep → Imbox/Feed/Paper Trail → sep →
    /// Set Aside →（弹性留白由视图处理）→ compose → settings(iOS) → syncNow → exitDemo(仅 demo)。
    public static func items(
        bucketCounts: [String: Int],
        isDemo: Bool,
        canCompose: Bool,
        isSyncCapable: Bool,
        showsSettings: Bool
    ) -> [Entry] {
        func count(_ bucket: Bucket) -> Int { bucketCounts[bucket.rawValue] ?? 0 }
        var items: [Entry] = [
            .bucket(.screener, count: count(.screener), expandable: false),
            .separator,
            .bucket(.imbox, count: count(.imbox), expandable: true),
            .bucket(.feed, count: count(.feed), expandable: true),
            .bucket(.paperTrail, count: count(.paperTrail), expandable: true),
            .separator,
            .bucket(.setAside, count: count(.setAside), expandable: false),
            .compose(enabled: canCompose),
        ]
        if showsSettings {
            items.append(.settings)
        }
        items.append(.syncNow(enabled: isSyncCapable))
        if isDemo {
            items.append(.exitDemo)
        }
        return items
    }
}
