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
    /// 邮件日期原文（JOURNEY-020：header-first 路径来自 ENVELOPE[0]，正文路径来自 MIME Date 头）。
    public var date: String?

    public init(stableMessageID: StableMessageID, uid: Int, flags: [String],
                raw: [UInt8], subject: String?, fromAddress: String?, date: String? = nil) {
        self.stableMessageID = stableMessageID
        self.uid = uid
        self.flags = flags
        self.raw = raw
        self.subject = subject
        self.fromAddress = fromAddress
        self.date = date
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
    /// 两段式同步（SYNC-013/PERF-003）：true 时列表同步只拉 ENVELOPE（不传正文），
    /// 正文由 fetchBody 按需拉取（SYNC-014）。业界邮件客户端通行做法（Apple Mail/Thunderbird）。
    public var headerFirst: Bool

    public init(accountFingerprint: String, initialWindow: Int = 200, headerFirst: Bool = true) {
        self.accountFingerprint = accountFingerprint
        self.initialWindow = initialWindow
        self.headerFirst = headerFirst
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
        let items = headerFirst ? "(UID FLAGS ENVELOPE)" : "(UID FLAGS BODY[])"
        let fetchLines = try ImapParser.parse(try transport.send(.fetchUid(range: range, items: items)))

        var events: [MailEvent] = []
        var highest = snapshot?.highestUid ?? 0
        for event in try Self.makeEvents(from: fetchLines, headerFirst: headerFirst,
                                         fingerprint: accountFingerprint) {
            events.append(event)
            highest = max(highest, event.uid)
        }

        let snap = SyncSnapshot(folder: folder, uidValidity: uidValidity, highestUid: highest)
        if isReset, let old = snapshot?.uidValidity {
            return .resetDetected(old: old, new: uidValidity, events: events, snapshot: snap)
        }
        return .synced(events: events, snapshot: snap)
    }

    /// 行 → 事件构造（列表同步与历史回填共用，SYNC-016）。
    static func makeEvents(from lines: [ParsedLine], headerFirst: Bool, fingerprint: String) throws -> [MailEvent] {
        var events: [MailEvent] = []
        for line in lines {
            guard let fd = FetchData.extract(from: line) else { continue }
            let rawBody = fd.rawBody ?? []
            let parsed = rawBody.isEmpty
                ? ParsedEmail(headers: [:], messageId: fd.messageId, subject: fd.subject,
                              from: fd.fromAddress, date: fd.envelopeDate, textBody: nil, htmlBody: nil, attachments: [])
                : MimeParser.parse(rawBody)
            guard !rawBody.isEmpty || fd.subject != nil || fd.fromAddress != nil else { continue }
            let stableID = StableMessageID(
                messageId: parsed.messageId ?? fd.messageId,
                accountFingerprint: fingerprint,
                fallback: .init(from: parsed.from ?? fd.fromAddress ?? "", date: parsed.date ?? "",
                                subject: parsed.subject ?? fd.subject ?? ""))
            events.append(MailEvent(
                stableMessageID: stableID, uid: fd.uid, flags: fd.flags, raw: rawBody,
                subject: parsed.subject ?? fd.subject, fromAddress: parsed.from ?? fd.fromAddress,
                date: parsed.date ?? fd.envelopeDate))
        }
        return events
    }

    /// 历史回填：拉任意 UID 区间（SYNC-016，后台回填器逐批调用）。
    public func fetchRange(_ range: String, transport: any ImapTransport) throws -> [MailEvent] {
        let lines = try ImapParser.parse(try transport.send(.fetchUid(range: range, items: "(UID FLAGS ENVELOPE)")))
        return try Self.makeEvents(from: lines, headerFirst: true, fingerprint: accountFingerprint)
    }

    /// 单封正文按需拉取（SYNC-014）：`FETCH uid (UID BODY.PEEK[])`——PEEK 不置 \Seen。
    /// 返回完整原文字节；邮件不在（已删）返回 nil。
    /// UID STORE 标记写回（MAIL-026）：\Seen 等本地动作尽力同步到服务器。
    /// FLAGS.SILENT 不回传新 flags（省流量）；失败抛错由调用方降级，不回滚本地。
    public func storeFlags(uid: Int, flags: [String], transport: any ImapTransport) throws {
        let response = String(decoding: try transport.send(.storeFlags(uid: uid, flags: flags)), as: UTF8.self)
        let failed = response.split(separator: "\r\n").contains { line in
            (line.hasPrefix("A") || line.hasPrefix("a")) && (line.contains(" NO ") || line.contains(" BAD "))
        }
        if failed { throw ImapStoreError.serverRejected }
    }

    /// UID MOVE 删除写回（MAIL-027）：把邮件移到目标文件夹（RFC 6851，UIDPLUS）。
    /// 失败抛错由调用方降级，不回滚本地删除（尽力而为）。
    public func move(uid: Int, to folder: String, transport: any ImapTransport) throws {
        let response = String(decoding: try transport.send(.move(uid: uid, folder: folder)), as: UTF8.self)
        let failed = response.split(separator: "\r\n").contains { line in
            (line.hasPrefix("A") || line.hasPrefix("a")) && (line.contains(" NO ") || line.contains(" BAD "))
        }
        if failed { throw ImapStoreError.serverRejected }
    }

    public func fetchBody(uid: Int, transport: any ImapTransport) throws -> [UInt8]? {
        let lines = try ImapParser.parse(try transport.send(.fetchUid(range: "\(uid)", items: "(UID BODY.PEEK[])")))
        for line in lines {
            if let fd = FetchData.extract(from: line), let body = fd.rawBody, !body.isEmpty {
                return body
            }
        }
        return nil
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
/// STORE 写回失败（MAIL-026）。
public enum ImapStoreError: Error, Equatable {
    case serverRejected
}
