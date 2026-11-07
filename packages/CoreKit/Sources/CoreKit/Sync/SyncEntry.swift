import Foundation

/// `Mailo/Sync` 文件夹内的 append-only 条目（基线 v3 §6）。
public enum SyncEntryKind: Hashable, Sendable, Codable {
    case classification(messageKey: String, bucket: Bucket)
    case ruleUpsert(UserRule)
    case ruleTombstone(ruleKey: String)
    /// 快照：历史条目的预合并状态（SYNC-005，防文件夹无限膨胀）。
    /// 载入语义 = 每条记录按同一决胜比较器逐项合并（乱序安全，旧快照不会回退状态）。
    case snapshot(SyncSnapshotPayload)
}

/// 快照载荷：MergeState 的 Codable 包装。
public struct SyncSnapshotPayload: Hashable, Sendable, Codable {
    public var state: MergeState

    public init(state: MergeState) {
        self.state = state
    }
}

public struct SyncEntry: Hashable, Sendable, Codable {
    public var id: String
    public var deviceId: String
    /// epoch 毫秒
    public var ts: Int64
    public var kind: SyncEntryKind

    public init(id: String = UUID().uuidString, deviceId: String, ts: Int64, kind: SyncEntryKind) {
        self.id = id
        self.deviceId = deviceId
        self.ts = ts
        self.kind = kind
    }
}
