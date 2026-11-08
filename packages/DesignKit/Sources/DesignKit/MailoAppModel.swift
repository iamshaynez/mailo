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
    @Published public private(set) var screenerCount: Int = 0
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
        lastSyncSummary = "同步 \(count) 封 · \(String(format: "%.1f", syncElapsed))s · imbox \(bucketCounts["imbox"] ?? 0) / feed \(bucketCounts["feed"] ?? 0) / paper \(bucketCounts["paperTrail"] ?? 0) / screener \(screenerCount)"
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
        tokenRefresher: (_ clientId: String, _ refreshToken: String) async throws -> String? = nil,
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
            return true
        } catch {
            return false
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
                    self.phase = .failed("同步失败：\(error)")
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Demo 模式切换（UI"先看看"入口）。
    public func switchToDemo() {
        Task { @MainActor in
            let demo = await MailoAppModel.bootstrapDemo(store: store)
            screenerCount = demo.screenerCount
            phase = .demo
            try? load(bucket: selectedBucket)
        }
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
                screenerCount += 1
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
        guard let raw = row.raw else {
            return MailDetail(stableId: stableId, subject: row.subject, fromAddress: row.fromAddress,
                              date: row.date, textBody: nil, htmlBody: nil,
                              attachmentNames: [], flags: row.flagList)
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
            flags: row.flagList)
    }

    /// 桶计数（load 后刷新，供侧栏徽章）。
    public private(set) var bucketCounts: [String: Int] = [:]

    public func refreshCounts() {
        bucketCounts = (try? store.bucketCounts()) ?? [:]
    }

    /// Screener 决策（CLS-010）：批准即显式规则，下一封同发件人直接命中；更新桶并刷新。
    public func decideScreener(stableId: String, to bucket: Bucket) throws {
        guard let row = try store.mail(stableId: stableId) else { return }
        if bucket != .screener, let from = row.fromAddress {
            let rule = UserRule.correction(senderAddress: from, bucket: bucket,
                                           deviceId: deviceId, ts: Int64(Date().timeIntervalSince1970 * 1000))
            pipeline.rules.append(rule)
        }
        try store.freeze(ClassificationRow(stableId: stableId, bucket: bucket, reason: "screenerDecision"))
        if let existing = pipeline.frozen.first(where: { $0.key.value == stableId })?.key {
            pipeline.frozen[existing] = bucket
        }
        try load(bucket: selectedBucket)
        refreshCounts()
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
