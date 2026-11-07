import CoreKit
import Foundation

/// 同步轮询编排策略（SYNC-011）：成功复位、失败指数退避封顶。
/// 这是零后端架构下"前台准实时"的外层循环引擎（基线 D7：前台 IDLE/轮询实时；
/// IDLE 长连接协议增强留 M1.5 真机阶段，见 DELIVERY §3）。
public struct PollingPolicy: Equatable, Sendable {
    public var baseIntervalSec: Int
    public var maxIntervalSec: Int
    public var currentIntervalSec: Int

    public init(baseIntervalSec: Int = 30, maxIntervalSec: Int = 300) {
        self.baseIntervalSec = baseIntervalSec
        self.maxIntervalSec = maxIntervalSec
        self.currentIntervalSec = baseIntervalSec
    }

    public mutating func onSuccess() {
        currentIntervalSec = baseIntervalSec
    }

    public mutating func onError() {
        currentIntervalSec = min(currentIntervalSec * 2, maxIntervalSec)
    }
}

/// 单文件夹同步的运行器：持有快照句柄，封装"取→同步→还"的往返。
public struct SyncRunner: Sendable {
    public var engine: ImapSyncEngine
    public var transport: any ImapTransport
    public var folder: String
    public private(set) var snapshot: SyncSnapshot?
    public private(set) var policy: PollingPolicy

    public init(accountFingerprint: String, transport: any ImapTransport,
                folder: String = "INBOX", policy: PollingPolicy = PollingPolicy()) {
        self.engine = ImapSyncEngine(accountFingerprint: accountFingerprint)
        self.transport = transport
        self.folder = folder
        self.policy = policy
    }

    /// 跑一轮：更新快照与轮询策略。返回本轮产出（失败抛错并退避）。
    @discardableResult
    public mutating func runOnce() throws -> SyncOutcome {
        do {
            let outcome = try engine.sync(folder: folder, snapshot: snapshot, transport: transport)
            switch outcome {
            case .synced(_, let snap), .resetDetected(_, _, _, let snap):
                snapshot = snap
            }
            policy.onSuccess()
            return outcome
        } catch {
            policy.onError()
            throw error
        }
    }
}
