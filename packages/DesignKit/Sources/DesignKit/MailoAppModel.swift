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

    public let store: MirrorStore
    public var pipeline: ClassificationPipeline
    public var deviceId: String

    private var runner: SyncRunner?
    private var pollTask: Task<Void, Never>?

    public init(store: MirrorStore, pipeline: ClassificationPipeline, deviceId: String = "device-A") {
        self.store = store
        self.pipeline = pipeline
        self.deviceId = deviceId
    }

    // MARK: - 数据源接入

    /// 注入传输的装配路径（JOURNEY-002；测试用 FakeImapServer，生产传 TcpImapTransport）。
    @discardableResult
    public func attach(account: CoreKit.AccountConfig, transport: any ImapTransport) throws -> SyncOutcome {
        var r = SyncRunner(accountFingerprint: account.fingerprint, transport: transport)
        let outcome = try r.runOnce()
        runner = r
        switch outcome {
        case .synced(let events, _), .resetDetected(_, _, let events, _):
            try apply(events)
        }
        phase = .connected(email: account.username)
        try load(bucket: selectedBucket)
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
            try attach(account: config, transport: transport)
            startPolling()
        } catch {
            phase = .failed(String(describing: error))
            throw error
        }
    }

    /// 前台轮询（基线 D7：30s 基准、失败退避由 PollingPolicy 管理）。
    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, var r = self.runner else { return }
                    do {
                        let outcome = try r.runOnce()
                        self.runner = r
                        if case .synced(let events, _) = outcome { try self.apply(events) }
                        try self.load(bucket: self.selectedBucket)
                    } catch {
                        self.phase = .failed("同步失败：\(error)")
                    }
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Demo 模式切换：Demo 数据写入共享 store 后切换呈现（UI"先看看"入口）。
    public func switchToDemo() {
        let demo = MailoAppModel.bootstrapDemo(store: store)
        screenerCount = demo.screenerCount
        phase = .demo
        try? load(bucket: selectedBucket)
    }

    // MARK: - 事件应用（入库 + 分类 + 冻结，JOURNEY-001 核心）

    public func apply(_ events: [MailEvent]) throws {
        for event in events {
            let parsed = MimeParser.parse(event.raw)
            let row = MailRow(
                stableId: event.stableMessageID.value,
                account: "primary", folder: "INBOX", uid: event.uid,
                flags: event.flags,
                subject: event.subject ?? parsed.subject,
                fromAddress: event.fromAddress ?? parsed.from,
                snippet: parsed.textBody.map { String($0.prefix(200)) },
                date: parsed.date,
                raw: Data(event.raw))
            try store.upsert(row)

            let signal = MailSignal(
                messageID: event.stableMessageID,
                senderLocalPart: row.fromAddress?.split(separator: "@").first.map(String.init) ?? "unknown",
                senderDomain: row.fromAddress?.split(separator: "@").last.map(String.init) ?? "unknown",
                subject: row.subject ?? "")
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
                pipeline.frozen[event.stableMessageID] = bucket
                try store.freeze(ClassificationRow(stableId: event.stableMessageID.value, bucket: bucket, reason: "\(reason)"))
            case .screener:
                screenerCount += 1
            }
        }
    }

    public func load(bucket: Bucket) throws {
        selectedBucket = bucket
        entries = try store.entries(bucket: bucket)
    }
}

/// 模型猜测的轻量注入点（MlKit 的 MlGateway 是 async 的；装配层用同步简化，app 层可桥接）。
public protocol MlGuessProviding: Sendable {
    func guess(for signal: MailSignal) throws -> ModelGuess
}

public extension MailoAppModel {
    /// Demo 装配：进程内假服务器，App"先看看"入口与 JOURNEY-001。
    @MainActor
    static func bootstrapDemo(store: MirrorStore? = nil) -> MailoAppModel {
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
        try? model.attach(account: demoAccount, transport: server)
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
