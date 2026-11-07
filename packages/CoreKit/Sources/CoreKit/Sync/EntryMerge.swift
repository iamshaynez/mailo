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
public struct MergeState: Equatable, Sendable, Codable {
    /// messageKey → 记录，first-writer-wins（SYNC-002）。
    public var classifications: [String: ClassificationRecord] = [:]
    /// ruleKey → 生效规则（LWW，SYNC-003）。
    public var rules: [String: UserRule] = [:]
    /// ruleKey → 删除标记（SYNC-004）。
    public var tombstones: [String: TombstoneRecord] = [:]

    public init() {}
}

/// 条目合并器：顺序无关、结果确定（SYNC-001）。
/// 决胜比较器统一为 (ts, deviceId) 元组字典序：
/// - 分类条目取**小者**（first-writer-wins，SYNC-002）
/// - 规则/墓碑取**大者**（LWW，SYNC-003/004）
public enum EntryMerge {
    public static func merge(_ state: inout MergeState, entries: some Sequence<SyncEntry>) {
        for entry in entries {
            switch entry.kind {
            case .classification(let key, let bucket):
                let incoming = ClassificationRecord(ts: entry.ts, deviceId: entry.deviceId, bucket: bucket)
                if let current = state.classifications[key] {
                    if (incoming.ts, incoming.deviceId) < (current.ts, current.deviceId) {
                        state.classifications[key] = incoming
                    }
                } else {
                    state.classifications[key] = incoming
                }

            case .ruleUpsert(let rule):
                let key = rule.matcher.key
                if let t = state.tombstones[key], (t.ts, t.deviceId) >= (rule.ts, rule.deviceId) {
                    continue // 被更新的墓碑压制（SYNC-004）
                }
                if let r = state.rules[key], (r.ts, r.deviceId) >= (rule.ts, rule.deviceId) {
                    continue // 已有更新版本（LWW）
                }
                state.rules[key] = rule
                state.tombstones[key] = nil // 新版本复活规则，旧墓碑退役

            case .ruleTombstone(let key):
                let incoming = TombstoneRecord(ts: entry.ts, deviceId: entry.deviceId)
                if let r = state.rules[key], (r.ts, r.deviceId) >= (incoming.ts, incoming.deviceId) {
                    continue // 现有规则更新，墓碑无效
                }
                if let t = state.tombstones[key], (t.ts, t.deviceId) >= (incoming.ts, incoming.deviceId) {
                    continue // 已有更新的墓碑
                }
                state.tombstones[key] = incoming
                state.rules[key] = nil

            case .snapshot(let payload):
                // 快照逐项按决胜比较器合并：乱序安全（旧快照/旧写不会回退状态，SYNC-005）
                for (key, rec) in payload.state.classifications {
                    let incoming = ClassificationRecord(ts: rec.ts, deviceId: rec.deviceId, bucket: rec.bucket)
                    if let current = state.classifications[key] {
                        if (incoming.ts, incoming.deviceId) < (current.ts, current.deviceId) {
                            state.classifications[key] = incoming
                        }
                    } else {
                        state.classifications[key] = incoming
                    }
                }
                for (key, rule) in payload.state.rules {
                    var synthetic = entry
                    synthetic.kind = .ruleUpsert(rule)
                    merge(&state, entries: [synthetic])
                }
                for (key, t) in payload.state.tombstones {
                    // 墓碑的 ts/deviceId 用快照记录的，而不是快照条目本身的
                    mergeTombstone(&state, key: key, record: TombstoneRecord(ts: t.ts, deviceId: t.deviceId))
                }
            }
        }
    }

    private static func mergeTombstone(_ state: inout MergeState, key: String, record: TombstoneRecord) {
        if let r = state.rules[key], (r.ts, r.deviceId) >= (record.ts, record.deviceId) {
            return // 现有规则更新，墓碑无效
        }
        if let t = state.tombstones[key], (t.ts, t.deviceId) >= (record.ts, record.deviceId) {
            return // 已有更新的墓碑
        }
        state.tombstones[key] = record
        state.rules[key] = nil
    }

    public static func merged(_ entries: some Sequence<SyncEntry>) -> MergeState {
        var s = MergeState()
        merge(&s, entries: entries)
        return s
    }
}
