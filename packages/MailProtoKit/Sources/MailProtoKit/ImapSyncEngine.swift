import CoreKit
import Foundation

/// 同步快照：文件夹级高水位（UIDVALIDITY + 最高已知 UID）。
public struct SyncSnapshot: Equatable, Sendable {
    public var folder: String
    public var uidValidity: Int
    public var highestUid: Int

    public init(folder: String, uidValidity: Int, highestUid: Int) {
        self.folder = folder
        self.uidValidity = uidValidity
        self.highestUid = highestUid
    }
}

/// 引擎产出的邮件事件：稳定主键 + 原始字节 + 摘要（供镜像层入库与分类管线消费）。
public struct MailEvent: Equatable, Sendable {
    public var stableMessageID: StableMessageID
    public var uid: Int
    public var flags: [String]
    public var raw: [UInt8]
    public var subject: String?
    public var fromAddress: String?

    public init(stableMessageID: StableMessageID, uid: Int, flags: [String],
                raw: [UInt8], subject: String?, fromAddress: String?) {
        self.stableMessageID = stableMessageID
        self.uid = uid
        self.flags = flags
        self.raw = raw
        self.subject = subject
        self.fromAddress = fromAddress
    }
}

/// 一次 sync 的产出（SYNC-006~008）。
public enum SyncOutcome: Equatable, Sendable {
    case synced(events: [MailEvent], snapshot: SyncSnapshot)
    case resetDetected(old: Int, new: Int, events: [MailEvent], snapshot: SyncSnapshot)
}

/// IMAP 同步引擎：SELECT → 能力感知的 FETCH → MailEvent 流（跑在任何 ImapTransport 上，
/// 生产 TCP 或 FakeImapServer）。纯同步逻辑，UI/存储层不在此处。
public struct ImapSyncEngine: Sendable {
    public var accountFingerprint: String

    public init(accountFingerprint: String) {
        self.accountFingerprint = accountFingerprint
    }

    public func sync(folder: String, snapshot: SyncSnapshot?, transport: any ImapTransport) throws -> SyncOutcome {
        // PLACEHOLDER (red phase)
        return .synced(events: [], snapshot: SyncSnapshot(folder: folder, uidValidity: 0, highestUid: 0))
    }
}