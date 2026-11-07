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
    /// 首次同步（无快照/重置重拉）的最近窗口：只拉最近 N 封，绝不全量
    /// （SYNC-012，基线 §5 回填策略"最近优先"；历史回填由后台分批任务负责）。
    public var initialWindow: Int

    public init(accountFingerprint: String, initialWindow: Int = 200) {
        self.accountFingerprint = accountFingerprint
        self.initialWindow = initialWindow
    }

    public func sync(folder: String, snapshot: SyncSnapshot?, transport: any ImapTransport) throws -> SyncOutcome {
        // 1. SELECT：状态聚合（EXISTS/UIDVALIDITY/UIDNEXT 经 SelectState 统一解析）
        let selectBytes = try transport.send(.select(folder: folder))
        let info = SelectState.parse(selectBytes)
        let uidValidity = Self.uidValidity(from: selectBytes)
        let exists = info.exists

        // 2. 重置检测（MAIL-006/SYNC-008）
        let previousState = snapshot.map { MailboxState(folder: $0.folder, uidValidity: $0.uidValidity, exists: 0) }
        let current = MailboxState(folder: folder, uidValidity: uidValidity, exists: exists)
        var isReset = false
        if case .uidValidityReset = SyncEvent.diff(previous: previousState, current: current) {
            isReset = true
        }

        // 3. 区间 FETCH：最近窗口（首次/重置）或高水位增量（SYNC-012）
        let range: String
        if snapshot == nil || isReset {
            range = info.uidNext > 0
                ? info.recentRange(count: initialWindow)
                : "1:*"
        } else {
            range = "\(snapshot!.highestUid + 1):*"
        }
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

    /// UIDVALIDITY 提取（tokenizer 中方括号为裸 token，按文本扫描稳健）。
    static func uidValidity(from bytes: [UInt8]) -> Int {
        let text = String(decoding: bytes, as: UTF8.self)
        for line in text.components(separatedBy: "\r\n") {
            if let r = line.range(of: "[UIDVALIDITY "), let end = line.range(of: "]", range: r.upperBound..<line.endIndex) {
                return Int(line[r.upperBound..<end.lowerBound]) ?? 0
            }
        }
        return 0
    }
}