import Foundation

/// `Mailo/Sync` 文件夹内的 append-only 条目（基线 v3 §6）。
public enum SyncEntryKind: Hashable, Sendable, Codable {
    case classification(messageKey: String, bucket: Bucket)
    case ruleUpsert(UserRule)
    case ruleTombstone(ruleKey: String)
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
