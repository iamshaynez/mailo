/// 分类合并记录（SYNC-002 决胜所需三元组）。
public struct ClassificationRecord: Equatable, Sendable {
    public var ts: Int64
    public var deviceId: String
    public var bucket: Bucket

    public init(ts: Int64, deviceId: String, bucket: Bucket) {
        self.ts = ts
        self.deviceId = deviceId
        self.bucket = bucket
    }
}

/// 规则删除标记记录（SYNC-004）。
public struct TombstoneRecord: Equatable, Sendable {
    public var ts: Int64
    public var deviceId: String

    public init(ts: Int64, deviceId: String) {
        self.ts = ts
        self.deviceId = deviceId
    }
}

/// CRDT 合并后的状态。
public struct MergeState: Equatable, Sendable {
    /// messageKey → 记录，first-writer-wins（SYNC-002）。
    public var classifications: [String: ClassificationRecord] = [:]
    /// ruleKey → 生效规则（LWW，SYNC-003）。
    public var rules: [String: UserRule] = [:]
    /// ruleKey → 删除标记（SYNC-004）。
    public var tombstones: [String: TombstoneRecord] = [:]

    public init() {}
}

/// 条目合并器：顺序无关、结果确定（SYNC-001）。
public enum EntryMerge {
    public static func merge(_ state: inout MergeState, entries: some Sequence<SyncEntry>) {
        // PLACEHOLDER (red phase)
        for _ in entries {}
    }

    public static func merged(_ entries: some Sequence<SyncEntry>) -> MergeState {
        var s = MergeState()
        merge(&s, entries: entries)
        return s
    }
}
