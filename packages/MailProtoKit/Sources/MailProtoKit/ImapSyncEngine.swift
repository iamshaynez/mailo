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
        // 1. SELECT：聚合 EXISTS 与 UIDVALIDITY
        let selectLines = try ImapParser.parse(try transport.send(.select(folder: folder)))
        var exists = 0, uidValidity = 0
        for line in selectLines {
            // * 3 EXISTS
            if line.atoms.count == 3, case .string(let star) = line.atoms[0], star == "*",
               case .string(let n) = line.atoms[1], let e = Int(n),
               case .string(let verb) = line.atoms[2], verb.uppercased() == "EXISTS" {
                exists = e
            }
            // * OK [UIDVALIDITY 7] ...
            if line.atoms.count >= 3, case .string(let star) = line.atoms[0], star == "*",
               case .string(let okv) = line.atoms[1], okv.uppercased() == "OK",
               case .list(let resp) = line.atoms[2], resp.count >= 2,
               case .string(let code) = resp[0], code.uppercased() == "UIDVALIDITY",
               case .string(let v) = resp[1], let uv = Int(v) {
                uidValidity = uv
            }
        }

        // 2. 重置检测（MAIL-006/MAIL/SYNC-008）
        let previousState = snapshot.map { MailboxState(folder: $0.folder, uidValidity: $0.uidValidity, exists: 0) }
        let current = MailboxState(folder: folder, uidValidity: uidValidity, exists: exists)
        var isReset = false
        if case .uidValidityReset = SyncEvent.diff(previous: previousState, current: current) {
            isReset = true
        }

        // 3. 区间 FETCH：全量（首次/重置）或高水位增量
        let range = (snapshot == nil || isReset) ? "1:*" : "\(snapshot!.highestUid + 1):*"
        let fetchLines = try ImapParser.parse(try transport.send(.fetchUid(range: range, items: "(UID FLAGS BODY[])")))

        var events: [MailEvent] = []
        var highest = snapshot?.highestUid ?? 0
        for line in fetchLines {
            guard let fd = FetchData.extract(from: line), let rawBody = fd.rawBody, !rawBody.isEmpty else { continue }
            let parsed = MimeParser.parse(rawBody)
            let stableID = StableMessageID(
                messageId: parsed.messageId,
                accountFingerprint: accountFingerprint,
                fallback: .init(from: parsed.from ?? "", date: parsed.date ?? "", subject: parsed.subject ?? ""))
            events.append(MailEvent(
                stableMessageID: stableID, uid: fd.uid, flags: fd.flags, raw: rawBody,
                subject: parsed.subject, fromAddress: parsed.from))
            highest = max(highest, fd.uid)
        }

        let snap = SyncSnapshot(folder: folder, uidValidity: uidValidity, highestUid: highest)
        if isReset, let old = snapshot?.uidValidity {
            return .resetDetected(old: old, new: uidValidity, events: events, snapshot: snap)
        }
        return .synced(events: events, snapshot: snap)
    }
}