/// CRDT 合并后的状态。
public struct MergeState: Hashable, Sendable {
    /// messageKey → (ts, deviceId, bucket)，first-writer-wins（SYNC-002）。
    public var classifications: [String: (ts: Int64, deviceId: String, bucket: Bucket)] = [:]
    /// ruleKey → 生效规则（LWW，SYNC-003）。
    public var rules: [String: UserRule] = [:]
    /// ruleKey → (ts, deviceId) 删除标记（SYNC-004）。
    public var tombstones: [String: (ts: Int64, deviceId: String)] = [:]

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
