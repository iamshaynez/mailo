import AuthKit
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit

/// App 根模型：组合同步引擎、镜像层与分类管线（JOURNEY-001/002 的装配点）。
/// 三种数据源：demo（进程内假服务器）/ 真实 Outlook（设备码授权+TCP）/ 注入传输（测试）。
@MainActor
public final class MailoAppModel: ObservableObject {
    public enum Phase: Equatable {
        case empty
        case demo
        case connecting(DeviceCodeClient.Prompt?)
        case connected(email: String)
        case failed(String)
    }

    @Published public private(set) var entries: [BucketEntry] = []
    @Published public private(set) var selectedBucket: Bucket = .imbox
    @Published public private(set) var phase: Phase = .empty
    /// 最近一轮同步诊断（底部状态条；排查"授权成功但列表空"这类问题的第一现场）
    @Published public private(set) var lastSyncSummary: String = ""

    public let store: MirrorStore
    public var pipeline: ClassificationPipeline
    public var deviceId: String

    private var runner: SyncRunner?
    private var accounts: AccountStore?

    private func accountStore() -> AccountStore {
        if let accounts { return accounts }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mailo", isDirectory: true)
        let store = AccountStore(directory: dir)
        accounts = store
        return store
    }
    // MARK: - UI 命令路由（JOURNEY-009）
    @Published public private(set) var commandRequest: MailCommandRequest?
    private var commandSeq = 0

    /// 手动同步可用（已装配 runner：demo/已连接）。
    public var isSyncCapable: Bool { runner != nil }

    /// 撰写可用（demo 或已连接）。
    public var canCompose: Bool {
        switch phase {
        case .demo, .connected: return true
        case .empty, .connecting, .failed: return false
        }
    }

    /// 菜单/快捷键 → 壳层动作（单调递增 id 保证重复触发可观察）。
    public func request(_ command: MailoUICommand) {
        commandSeq += 1
        commandRequest = MailCommandRequest(id: commandSeq, command: command)
    }

    /// 手动同步（JOURNEY-009 菜单）：立即跑一轮增量并刷新列表；失败写入同步摘要不弹窗。
    public func syncNow() {
        Task { @MainActor in
            guard var r = runner else { return }
            do {
                let outcome = try r.runOnce()
                runner = r
                if case .synced(let events, _) = outcome {
                    try? await apply(events)
                    try? store.saveSnapshot(folder: "INBOX",
                                            uidValidity: r.snapshot?.uidValidity ?? 0,
                                            highestUid: r.snapshot?.highestUid ?? 0)
                }
                try load(bucket: selectedBucket)
                lastSyncSummary = "Manual sync completed"
            } catch {
                lastSyncSummary = "Sync failed: \(error)"
            }
        }
    }
    private var pollTask: Task<Void, Never>?

    public init(store: MirrorStore, pipeline: ClassificationPipeline, deviceId: String = "device-A") {
        self.store = store
        self.pipeline = pipeline
        self.deviceId = deviceId
    }

    // MARK: - 数据源接入

    /// 注入传输的装配路径（JOURNEY-002；测试用 FakeImapServer，生产传 TcpImapTransport）。
    /// 快照从本地库恢复（SYNC-015：重启只拉增量），同步后持久化。
    @discardableResult
    public func attach(account: CoreKit.AccountConfig, transport: any ImapTransport) async throws -> SyncOutcome {
        var r = SyncRunner(accountFingerprint: account.fingerprint, transport: transport)
        // 恢复持久化快照（若上次同步过）
        if let saved = store.loadSnapshot(folder: "INBOX") {
            r.restoreSnapshot(SyncSnapshot(folder: "INBOX", uidValidity: saved.uidValidity, highestUid: saved.highestUid))
        }
        let started = Date()
        let outcome = try r.runOnce()
        runner = r
        try store.saveSnapshot(folder: "INBOX", uidValidity: r.snapshot?.uidValidity ?? 0,
                               highestUid: r.snapshot?.highestUid ?? 0)
        var count = 0
        switch outcome {
        case .synced(let events, _), .resetDetected(_, _, let events, _):
            try await apply(events)
            count = events.count
        }
        phase = .connected(email: account.username)
        try load(bucket: selectedBucket)
        syncElapsed = Date().timeIntervalSince(started)
        lastSyncSummary = "Synced \(count) · \(String(format: "%.1f", syncElapsed))s · imbox \(bucketCounts["imbox"] ?? 0) / feed \(bucketCounts["feed"] ?? 0) / paper \(bucketCounts["paperTrail"] ?? 0) / screener \(screenerCount)"
        return outcome
    }

    /// 真实 Outlook：设备码授权 → XOAUTH2 连接 → 首轮同步（JOURNEY-002 生产路径）。
    /// token 只入内存 + vault（refresh token），授权提示经 phase 广播给 UI。
    public func connectOutlook(
        email: String, clientId: String,
        account: DeviceCodeFlow.MicrosoftAccount = .personal,
        vault: (any CredentialVault)? = nil
    ) async throws {
        phase = .connecting(nil)
        do {
            let client = DeviceCodeClient()
            let granted = try await client.authorize(clientId: clientId, account: account) { [weak self] prompt in
                self?.phase = .connecting(prompt)
            }
            if let vault {
                // refresh token 持久化（下次启动免授权）；access token 不落盘
                try? vault.save(granted.refreshToken ?? granted.accessToken, for: "mailo.acct.outlook.\(email)")
            }
            let transport = TcpImapTransport(host: OAuthProviderConfig.outlookImapHost, port: 993, connectTimeout: 15)
            try transport.connect(method: .xoauth2(user: email, accessToken: granted.accessToken))

            let config = AccountConfig(
                displayName: email, imapHost: OAuthProviderConfig.outlookImapHost,
                smtpHost: OAuthProviderConfig.outlookSmtpHost, username: email,
                secretRef: "mailo.acct.outlook.\(email)")
            try await attach(account: config, transport: transport)
            try? accountStore().save(AccountRecord(email: email, clientId: clientId,
                                                   accountKind: account, secretRef: config.secretRef))
            startPolling()
            startBackfill()
        } catch {
            phase = .failed(String(describing: error))
            throw error
        }
    }

    /// 恢复上次会话（JOURNEY-005）：refresh token 刷新 → 连接 → 增量同步，免设备码。
    /// tokenRefresher / transportFactory 为注入点（生产默认 DeviceCodeClient/TCP；测试注入假件）。
    @discardableResult
    public func restoreSavedAccount(
        vault: any CredentialVault,
        directory: URL? = nil,
        tokenRefresher: ((_ clientId: String, _ refreshToken: String) async throws -> String?)? = nil,
        transportFactory: (_ host: String) -> any ImapTransport = { TcpImapTransport(host: $0) }
    ) async -> Bool {
        let store: AccountStore = {
            if let directory { return AccountStore(directory: directory) }
            return accountStore()
        }()
        guard let record = store.loadPrimary(),
              let secret = try? vault.load(record.secretRef), !secret.isEmpty else { return false }
        let kind = DeviceCodeFlow.MicrosoftAccount(rawValue: record.accountKind) ?? .personal
        do {
            let accessToken: String?
            if let refresher = tokenRefresher {
                accessToken = try await refresher(record.clientId, secret)
            } else {
                let granted = try await DeviceCodeClient().refresh(
                    clientId: record.clientId, account: kind, refreshToken: secret)
                accessToken = granted.accessToken
            }
            guard let token = accessToken else { return false }
            let transport = transportFactory(OAuthProviderConfig.outlookImapHost)
            try (transport as? TcpImapTransport)?.connect(method: .xoauth2(user: record.email, accessToken: token))
            let config = AccountConfig(displayName: record.email,
                                       imapHost: OAuthProviderConfig.outlookImapHost,
                                       smtpHost: OAuthProviderConfig.outlookSmtpHost,
                                       username: record.email, secretRef: record.secretRef)
            try await attach(account: config, transport: transport)
            startPolling()
            startBackfill()
            return true
        } catch {
            return false
        }
    }

    /// 历史回填（SYNC-016）：从最近窗口下沿逐批向 UID 1 推进，覆盖全量信封。
    /// 每批一条命令、间隔 2 秒防压服务器；空批 = UID 空洞继续；到 1 收尾。
    private var backfillTask: Task<Void, Never>?
    public private(set) var backfilledCount = 0

    public func startBackfill(batchSize: Int = 100) {
        backfillTask?.cancel()
        guard let runner else { return }
        let floor0 = max(1, (runner.snapshot?.highestUid ?? 0) - runner.engine.initialWindow)
        guard floor0 > 1 else { return }
        backfillTask = Task { [weak self] in
            var floor = floor0
            while !Task.isCancelled, let self {
                guard let r = self.runner else { return }
                let low = max(1, floor - batchSize + 1)
                if let events = try? r.engine.fetchRange("\(low):\(floor)", transport: r.transport), !events.isEmpty {
                    try? await self.apply(events)
                    self.backfilledCount += events.count
                    self.lastSyncSummary = "Backfilled \(self.backfilledCount) · UID \(low)"
                    self.refreshCounts()
                    self.entries = (try? self.store.entries(bucket: self.selectedBucket)) ?? self.entries
                }
                if low <= 1 { 
                    self.lastSyncSummary = "Backfill complete: \(self.backfilledCount) mails"
                    return 
                }
                floor = low - 1
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// 前台轮询（基线 D7：30s 基准、失败退避由 PollingPolicy 管理）。
    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in // Task 继承 MainActor（类隔离）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard var r = self.runner else { continue }
                do {
                    let outcome = try r.runOnce()
                    self.runner = r
                    if case .synced(let events, _) = outcome {
                        try? await self.apply(events)
                        try? self.store.saveSnapshot(folder: "INBOX",
                            uidValidity: r.snapshot?.uidValidity ?? 0,
                            highestUid: r.snapshot?.highestUid ?? 0)
                    }
                    try self.load(bucket: self.selectedBucket)
                } catch {
                    // 轮询失败不降级 UI（连接仍在、退避重试；MAIL-025）
                    self.lastSyncSummary = "Sync retrying: \(error)"
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - 撰写与搜索（JOURNEY-006/007）

    @Published public private(set) var searchResults: [MirrorKit.MailRow] = []

    /// 撰写并发送（JOURNEY-006）：refresh token → access token → SMTP XOAUTH2。
    /// tokenRefresher / smtpTransport 为注入点（生产默认 DeviceCodeClient/TCP；测试注入假件）。
    public func composeAndSend(
        to: String, subject: String, body: String,
        vault: (any CredentialVault)? = nil,
        directory: URL? = nil,
        tokenRefresher: ((_ clientId: String, _ refreshToken: String) async throws -> String?)? = nil,
        smtpTransport: (any SmtpTransport)? = nil
    ) async throws {
        let store: AccountStore = directory.map { AccountStore(directory: $0) } ?? accountStore()
        guard let record = store.loadPrimary() else {
            throw ComposeError.notConnected
        }
        let vault = vault ?? InMemoryVault() // 生产由 UI 传 KeychainVault；此处兜底避免崩溃
        guard let secret = try? vault.load(record.secretRef), !secret.isEmpty else {
            throw ComposeError.missingToken
        }
        let accessToken: String
        if let refresher = tokenRefresher {
            guard let refreshed = try await refresher(record.clientId, secret) else {
                throw ComposeError.refreshFailed
            }
            accessToken = refreshed
        } else {
            let kind = DeviceCodeFlow.MicrosoftAccount(rawValue: record.accountKind) ?? .personal
            accessToken = try await DeviceCodeClient().refresh(clientId: record.clientId, account: kind, refreshToken: secret).accessToken
        }
        let transport = smtpTransport ?? TcpSmtpTransport(host: OAuthProviderConfig.outlookSmtpHost, port: 465)
        try (transport as? TcpSmtpTransport)?.connect()
        _ = try SmtpClient().send(from: record.email, to: to, subject: subject, body: body,
                                  auth: .xoauth2(user: record.email, accessToken: accessToken),
                                  transport: transport)
        lastSyncSummary = "Sent to \(to): \(subject)"
    }

    public enum ComposeError: Error, Equatable {
        case notConnected
        case missingToken
        case refreshFailed
    }

    /// 全文搜索（JOURNEY-007）：FTS5/底层搜索的 UI 数据源。
    public func search(_ query: String) {
        guard query.trimmingCharacters(in: .whitespaces).count >= 1 else {
            searchResults = []
            return
        }
        searchResults = (try? store.search(query)) ?? []
    }

    // MARK: - 事件应用（入库 + 分类 + 冻结，JOURNEY-001 核心）

    /// 同步耗时（诊断条）
    public private(set) var syncElapsed: TimeInterval = 0

    /// 事件应用（JOURNEY-001 核心）：MIME 解析在后台线程（防主线程卡顿），
    /// 批量单事务写库（STORE-007），冻结合并回主线程后刷新。
    public func apply(_ events: [MailEvent]) async throws {
        guard !events.isEmpty else { return }
        // 后台：解析与行构造（MimeParser 纯函数、线程安全）
        let fingerprint = "primary"
        let prepared: [(row: MailRow, stable: StableMessageID, signal: MailSignal, frozenAlready: Bool)] = await Task.detached(priority: .userInitiated) { [pipeline] () -> [(MailRow, StableMessageID, MailSignal, Bool)] in
            events.map { event in
                let parsed = MimeParser.parse(event.raw)
                let rawBody = event.raw
                let from = EmailAddress.parse(event.fromAddress)?.address
                    ?? EmailAddress.parse(parsed.from)?.address
                    ?? parsed.from
                let row = MailRow(
                    stableId: event.stableMessageID.value,
                    account: "primary", folder: "INBOX", uid: event.uid,
                    flags: event.flags,
                    subject: event.subject ?? parsed.subject,
                    fromAddress: from,
                    snippet: rawBody.isEmpty ? nil : parsed.textBody.map { String($0.prefix(200)) },
                    date: parsed.date, raw: rawBody.isEmpty ? nil : Data(rawBody))
                let fromParsed = EmailAddress.parse(from)
                let signal = MailSignal(
                    messageID: event.stableMessageID,
                    senderLocalPart: fromParsed?.local ?? "unknown",
                    senderDomain: fromParsed?.domain ?? "unknown",
                    subject: row.subject ?? "")
                return (row, event.stableMessageID, signal, pipeline.frozen[event.stableMessageID] != nil)
            }
        }.value

        var rows: [MailRow] = []
        var newFrozen: [(StableMessageID, Bucket, String)] = []
        for (row, stable, signal, alreadyFrozen) in prepared {
            rows.append(row)
            guard !alreadyFrozen else { continue } // 冻结幂等（CLS-005）
            let verdict = pipeline.decide(signal)
            let decision: FinalDecision
            switch verdict {
            case .classified:
                decision = ClassificationPipeline.applyModel(verdict, guess: ModelGuess(bucket: .screener, confidence: 0))
            case .needsModel:
                decision = ClassificationPipeline.applyModel(
                    verdict, guess: ModelGuess(bucket: .screener, confidence: 0.3)) // 待 MlKit 真模型接入
            }
            switch decision {
            case .bucket(let bucket, let reason):
                newFrozen.append((stable, bucket, "\(reason)"))
            case .screener:
                newFrozen.append((stable, .screener, "belowThreshold"))
            }
        }
        // 批量写（单事务）
        try store.upsertBatch(rows)
        try store.freezeBatch(newFrozen.map { ClassificationRow(stableId: $0.0.value, bucket: $0.1, reason: $0.2) })
        for (stable, bucket, _) in newFrozen {
            pipeline.frozen[stable] = bucket
        }
    }


/// 模型猜测的轻量注入点（MlKit 的 MlGateway 是 async 的；装配层用同步简化，app 层可桥接）。
public protocol MlGuessProviding: Sendable {
    func guess(for signal: MailSignal) throws -> ModelGuess
}

    // MARK: - 支撑能力（CLS-010 / STORE-006 / JOURNEY-003/004）

    /// 邮件详情（阅读窗格数据源；两段式下正文按需回填，SYNC-014）。
    public struct MailDetail: Equatable, Sendable {
        public var stableId: String
        public var subject: String?
        public var fromAddress: String?
        public var date: String?
        public var textBody: String?
        public var htmlBody: String?
        public var attachmentNames: [String]
        public var flags: [String]
        /// 邮件自身的归类桶（徽标/头像语义色用这个，而非当前列表桶）
        public var bucket: Bucket?

        public var isUnread: Bool { !flags.contains("\\Seen") }
    }

    public func mailDetail(stableId: String) -> MailDetail? {
        guard var row = try? store.mail(stableId: stableId) else { return nil }
        if row.raw == nil, let runner {
            if let body = try? runner.engine.fetchBody(uid: row.uid, transport: runner.transport) {
                let parsed = MimeParser.parse(body)
                row.raw = Data(body)
                row.snippet = row.snippet ?? parsed.textBody.map { String($0.prefix(200)) }
                try? store.upsert(row)
            }
        }
        let ownBucket = try? store.classificationBucket(stableId: stableId)
        guard let raw = row.raw else {
            return MailDetail(stableId: stableId, subject: row.subject, fromAddress: row.fromAddress,
                              date: row.date, textBody: nil, htmlBody: nil,
                              attachmentNames: [], flags: row.flagList, bucket: ownBucket)
        }
        let parsed = MimeParser.parse([UInt8](raw))
        return MailDetail(
            stableId: stableId,
            subject: row.subject ?? parsed.subject,
            fromAddress: row.fromAddress ?? parsed.from,
            date: row.date ?? parsed.date,
            textBody: parsed.textBody,
            htmlBody: parsed.htmlBody,
            attachmentNames: parsed.attachments.compactMap(\.filename),
            flags: row.flagList,
            bucket: ownBucket)
    }

    /// 桶计数（load 后刷新，供侧栏徽章）。
    public private(set) var bucketCounts: [String: Int] = [:]

    /// Screener 待定数（STORE-006 计数的单一来源；决策/Block 后自动消减）。
    public var screenerCount: Int { bucketCounts[Bucket.screener.rawValue] ?? 0 }

    public func refreshCounts() {
        bucketCounts = (try? store.bucketCounts()) ?? [:]
    }

    // MARK: - 阅读与桶动作（JOURNEY-012/013/017 · CLS-011）

    /// 当前阅读选中（菜单可用性与 Reply/Forward 目标；壳层在 selection 变化时同步）。
    @Published public private(set) var readingStableId: String?

    public func setReading(_ stableId: String?) {
        readingStableId = stableId
    }

    /// 最近一次可撤销动作（Edit ⌘Z 消费）。
    @Published public private(set) var lastAction: UndoableAction?

    /// 打开即标已读（JOURNEY-013）：本地 flags 并集（未读点立即消失），
    /// 服务器 UID STORE 写回在后台尽力而为，失败不回滚本地。
    public func markRead(stableId: String) {
        try? store.setFlags(stableId: stableId, merge: ["\\Seen"])
        entries = (try? store.entries(bucket: selectedBucket)) ?? entries
        refreshCounts()
        // 服务器写回（尽力而为）：后台线程，失败不回滚本地（JOURNEY-013）
        guard let runner, let row = try? store.mail(stableId: stableId) else { return }
        let engine = runner.engine, transport = runner.transport, uid = row.uid
        Task.detached(priority: .utility) {
            _ = try? engine.storeFlags(uid: uid, flags: ["\\Seen"], transport: transport)
        }
    }

    /// 标回未读（仅本地；服务器写回不做——重新打开会再次标读）。
    public func markUnread(stableId: String) {
        try? store.setFlags(stableId: stableId, remove: ["\\Seen"])
        entries = (try? store.entries(bucket: selectedBucket)) ?? entries
    }

    public func toggleUnread(stableId: String) {
        let isUnread = (try? store.mail(stableId: stableId))?.flagList.contains("\\Seen") != true
        if isUnread { markRead(stableId: stableId) } else { markUnread(stableId: stableId) }
    }

    /// 服务器写回（MAIL-026；可测入口）：UID STORE +FLAGS (\\Seen)。
    public func storeSeenOnServer(stableId: String) throws {
        guard let runner, let row = try store.mail(stableId: stableId) else { return }
        try runner.engine.storeFlags(uid: row.uid, flags: ["\\Seen"], transport: runner.transport)
    }

    /// 测试钩子：装配后的传输（假服务器断言服务器侧 flags）。
    public var runnerDebugTransport: (any ImapTransport)? { runner?.transport }

    /// Set Aside（JOURNEY-012）：仅本封迁移（不生成发件人规则）；⌘Z 可撤销。
    public func setAside(stableId: String) throws {
        let previous = try store.classificationBucket(stableId: stableId) ?? selectedBucket
        try refreeze(stableId: stableId, to: .setAside, reason: "setAside")
        try load(bucket: selectedBucket)
        registerUndo(label: "Set Aside") { [weak self] in
            guard let self else { return }
            try? self.refreeze(stableId: stableId, to: previous, reason: "undoSetAside")
            try? self.load(bucket: self.selectedBucket)
        }
    }

    /// Screener 决策（CLS-010/011）：批准/拦截均生成显式规则（Block → blocked 桶），
    /// 同发件人待定件全部迁移；下一封同发件人直接命中规则。
    public func decideScreener(stableId: String, to bucket: Bucket) throws {
        try reclassify(stableId: stableId, to: bucket, label: "Screener Decision")
    }

    /// 手动纠正（JOURNEY-017 / CLS-006 语义）：senderExact→目标桶 显式规则 +
    /// 同发件人既有待定件全部迁移；撤销回原桶并移除规则。
    public func reclassify(stableId: String, to bucket: Bucket) throws {
        try reclassify(stableId: stableId, to: bucket, label: "Reclassify")
    }

    private func reclassify(stableId: String, to bucket: Bucket, label: String) throws {
        guard let row = try store.mail(stableId: stableId) else { return }
        let previous = try store.classificationBucket(stableId: stableId) ?? selectedBucket
        var ruleId: UUID?
        if let from = row.fromAddress {
            let rule = UserRule.correction(senderAddress: from, bucket: bucket,
                                           deviceId: deviceId, ts: Int64(Date().timeIntervalSince1970 * 1000))
            pipeline.rules.append(rule)
            ruleId = rule.id
        }
        // 同发件人待定件（含本封若在 Screener）全部迁移
        var moved: [(String, Bucket)] = [(stableId, previous)]
        if let from = row.fromAddress {
            let pending = (try? store.entries(bucket: .screener))?
                .filter { $0.fromAddress == from && $0.stableId != stableId } ?? []
            for entry in pending {
                moved.append((entry.stableId, .screener))
                try refreeze(stableId: entry.stableId, to: bucket, reason: "ruleMigration")
            }
        }
        try refreeze(stableId: stableId, to: bucket, reason: "manualCorrection")
        try load(bucket: selectedBucket)
        let capturedRuleId = ruleId
        registerUndo(label: label) { [weak self] in
            guard let self else { return }
            if let capturedRuleId {
                self.pipeline.rules.removeAll { $0.id == capturedRuleId }
            }
            for (id, back) in moved {
                try? self.refreeze(stableId: id, to: back, reason: "undoCorrection")
            }
            try? self.load(bucket: self.selectedBucket)
        }
    }

    private func refreeze(stableId: String, to bucket: Bucket, reason: String) throws {
        try store.freeze(ClassificationRow(stableId: stableId, bucket: bucket, reason: reason))
        if let existing = pipeline.frozen.first(where: { $0.key.value == stableId })?.key {
            pipeline.frozen[existing] = bucket
        }
    }

    private func registerUndo(label: String, perform: @escaping @MainActor () -> Void) {
        lastAction = UndoableAction(label: label, perform: perform)
    }

    /// Edit ▸ Undo（⌘Z）：撤销最近一次桶动作。
    public func undoLast() {
        lastAction?.perform()
        lastAction = nil
    }

    // MARK: - 撰写预填（JOURNEY-011）

    /// Reply/Forward 草稿构造（不触发网络；正文引用用 snippet/已回填正文）。
    public func composeDraft(for stableId: String, kind: ComposeDraft.Kind) -> ComposeDraft? {
        guard let row = try? store.mail(stableId: stableId) else { return nil }
        let quote: String?
        if let raw = row.raw {
            quote = MimeParser.parse([UInt8](raw)).textBody ?? row.snippet
        } else {
            quote = row.snippet
        }
        switch kind {
        case .compose:
            return ComposeDraft()
        case .reply:
            return ComposeDraft(kind: .reply, to: row.fromAddress ?? "",
                                subject: ComposeDraft.replySubject(row.subject),
                                body: ComposeDraft.replyBody(quote: quote, from: row.fromAddress))
        case .forward:
            return ComposeDraft(kind: .forward, to: "",
                                subject: ComposeDraft.forwardSubject(row.subject),
                                body: ComposeDraft.forwardBody(quote: quote, from: row.fromAddress,
                                                               subject: row.subject, date: row.date))
        }
    }

    public func load(bucket: Bucket) throws {
        selectedBucket = bucket
        entries = try store.entries(bucket: bucket)
        refreshCounts()
    }
}

public extension MailoAppModel {
    /// Demo 装配：进程内假服务器，App"先看看"入口与 JOURNEY-001。
    @MainActor
    static func bootstrapDemo(store: MirrorKit.MirrorStore? = nil) async -> MailoAppModel {
        let s: MirrorStore
        do { s = try store ?? MirrorStore() } catch { fatalError("in-memory store cannot fail") }
        let roster = Roster(domainBuckets: [
            "netflix.com": .feed, "amzn.com": .paperTrail, "wave.co": .imbox,
        ])
        let model = MailoAppModel(store: s, pipeline: ClassificationPipeline(roster: roster))
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 1, raw: Array("Message-ID: <d1@x.t>\r\nFrom: alerts@netflix.com\r\nSubject: New season\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\n\r\nWatch now".utf8)),
            Message(uid: 2, raw: Array("Message-ID: <d2@x.t>\r\nFrom: receipt@amzn.com\r\nSubject: Your order shipped\r\nDate: Fri, 7 Nov 2026 11:00:00 +0000\r\n\r\nOn the way".utf8)),
            Message(uid: 3, raw: Array("Message-ID: <d3@x.t>\r\nFrom: sarah@wave.co\r\nSubject: Re: contract\r\nDate: Fri, 7 Nov 2026 12:00:00 +0000\r\n\r\nClause 4 updated".utf8)),
            Message(uid: 4, raw: Array("Message-ID: <d4@x.t>\r\nFrom: stranger@unknown.co\r\nSubject: hello?\r\nDate: Fri, 7 Nov 2026 13:00:00 +0000\r\n\r\nfirst time".utf8)),
        ])])
        let demoAccount = AccountConfig(displayName: "Demo", imapHost: "demo.local",
                                        smtpHost: "demo.local", username: "demo@local",
                                        secretRef: "demo")
        try? await model.attach(account: demoAccount, transport: server)
        model.phase = .demo
        return model
    }
}


public extension MailoAppModel {
    /// 生产工厂：app support 文件库（跨启动持久）+ 内置种子名单库。
    @MainActor
    static func createLive(storeDirectory: URL? = nil) -> MailoAppModel {
        let dir = storeDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Mailo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("mailo.sqlite").path
        let store = (try? MirrorStore(path: dbPath)) ?? (try? MirrorStore())
        return MailoAppModel(
            store: store ?? { fatalError("mirror store unavailable") }(),
            pipeline: ClassificationPipeline(roster: RosterSeed.roster()))
    }
}
