import Foundation

/// 同步模式：按服务器能力协商，宁降级不失败（MAIL-007 / 基线 §4 能力协商矩阵）。
public enum SyncMode: Equatable, Sendable {
    case qresync
    case condstore
    case full

    /// 协商：QRESYNC > CONDSTORE > 全量。
    public static func negotiate(capabilities: [String]) -> SyncMode {
        let caps = Set(capabilities.map { $0.uppercased() })
        if caps.contains("QRESYNC") { return .qresync }
        if caps.contains("CONDSTORE") { return .condstore }
        return .full
    }
}

/// SELECT 聚合状态（用于 UIDVALIDITY 检测）。
public struct MailboxState: Equatable, Sendable {
    public var folder: String
    public var uidValidity: Int
    public var exists: Int

    public init(folder: String, uidValidity: Int, exists: Int) {
        self.folder = folder
        self.uidValidity = uidValidity
        self.exists = exists
    }
}

/// 同步引擎关注的会话事件（MAIL-006：UIDVALIDITY 重置 → 按稳定主键重拉，分类不丢）。
public enum SyncEvent: Equatable, Sendable {
    case uidValidityReset(folder: String, old: Int, new: Int)
    case mailboxReady(MailboxState)

    /// 对比前后两次 SELECT 状态；uidValidity 变化即重置事件（首次 SELECT 不算）。
    public static func diff(previous: MailboxState?, current: MailboxState) -> SyncEvent {
        if let prev = previous, prev.uidValidity != current.uidValidity {
            return .uidValidityReset(folder: current.folder, old: prev.uidValidity, new: current.uidValidity)
        }
        return .mailboxReady(current)
    }
}
