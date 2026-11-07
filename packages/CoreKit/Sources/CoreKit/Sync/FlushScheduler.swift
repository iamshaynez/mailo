import Foundation

/// `Mailo/Sync` 本地写队列的 flush 节流器（基线 §6：30s 或 20 条批写）。
public struct FlushScheduler: Sendable, Equatable {
    public var maxEntries: Int
    public var maxDelayMs: Int64
    public private(set) var pending: [SyncEntry] = []

    public init(maxEntries: Int = 20, maxDelayMs: Int64 = 30_000) {
        self.maxEntries = maxEntries
        self.maxDelayMs = maxDelayMs
    }

    /// 入队一条；返回是否应立即 flush（满 maxEntries）。
    @discardableResult
    public mutating func enqueue(_ entry: SyncEntry) -> Bool {
        // PLACEHOLDER (red phase)
        pending.append(entry)
        return false
    }

    /// 定时器触发；最老 pending 超过 maxDelayMs 则 flush。
    public mutating func timerFired(now: Int64) -> Bool {
        // PLACEHOLDER (red phase)
        return false
    }

    /// 取走全部 pending（flush 时调用）。
    public mutating func drain() -> [SyncEntry] {
        let out = pending
        pending = []
        return out
    }
}
