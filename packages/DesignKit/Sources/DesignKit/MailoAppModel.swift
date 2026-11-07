import CoreKit
import Foundation
import MailProtoKit
import MirrorKit

/// App 根模型：组合同步引擎、镜像层与分类管线（JOURNEY-001 的装配点）。
/// bootstrap 用进程内 FakeImapServer——零网络即可跑通"同步→入库→分类→呈现"全链路，
/// UI 开发与测试的地基；生产 TCP 传输实现接入后替换 transport 即可。
@MainActor
public final class MailoAppModel: ObservableObject {
    @Published public private(set) var entries: [BucketEntry] = []
    @Published public private(set) var screenerCount: Int = 0
    @Published public private(set) var selectedBucket: Bucket = .imbox

    public let store: MirrorStore
    public var pipeline: ClassificationPipeline
    public var deviceId: String

    public init(store: MirrorStore, pipeline: ClassificationPipeline, deviceId: String = "device-A") {
        self.store = store
        self.pipeline = pipeline
        self.deviceId = deviceId
    }

    /// 端到端装配（JOURNEY-001）：同步 → MIME 摘要 → 镜像入库 → 管线判定 → 冻结 → 列表。
    @discardableResult
    public func syncAndClassify(folder: String = "INBOX", transport: any ImapTransport,
                                snapshot: SyncSnapshot? = nil,
                                gateway: (any MlGuessProviding)? = nil) throws -> SyncSnapshot {
        let engine = ImapSyncEngine(accountFingerprint: "demo")
        let outcome = try engine.sync(folder: folder, snapshot: snapshot, transport: transport)

        let events: [MailEvent]
        switch outcome {
        case .synced(let e, _), .resetDetected(_, _, let e, _):
            events = e
        }

        for event in events {
            let parsed = MimeParser.parse(event.raw)
            let row = MailRow(
                stableId: event.stableMessageID.value,
                account: "demo", folder: folder, uid: event.uid,
                flags: event.flags,
                subject: event.subject ?? parsed.subject,
                fromAddress: event.fromAddress ?? parsed.from,
                snippet: parsed.textBody.map { String($0.prefix(200)) },
                date: parsed.date,
                raw: Data(event.raw))
            try store.upsert(row)

            // 管线判定（冻结 > 规则 > 名单库 > 模型）
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
                let guess = try gateway?.guess(for: signal) ?? ModelGuess(bucket: .screener, confidence: 0.3)
                decision = ClassificationPipeline.applyModel(verdict, guess: guess)
            }
            switch decision {
            case .bucket(let bucket, let reason):
                pipeline.frozen[event.stableMessageID] = bucket
                try store.freeze(ClassificationRow(stableId: event.stableMessageID.value, bucket: bucket, reason: "\(reason)"))
            case .screener:
                screenerCount += 1
            }
        }
        try load(bucket: selectedBucket)
        switch outcome {
        case .synced(_, let snap), .resetDetected(_, _, _, let snap):
            return snap
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
    /// Demo 装配：进程内假服务器 + 内存库，App 壳直接可用（JOURNEY-001 的生产化形态）。
    @MainActor
    static func bootstrapDemo() -> MailoAppModel {
        let store: MirrorStore
        do { store = try MirrorStore() } catch { fatalError("in-memory store cannot fail") }
        let roster = Roster(domainBuckets: [
            "netflix.com": .feed, "amzn.com": .paperTrail, "wave.co": .imbox,
        ])
        let model = MailoAppModel(store: store, pipeline: ClassificationPipeline(roster: roster))
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 7, messages: [
            Message(uid: 1, raw: Array("Message-ID: <d1@x.t>\r\nFrom: alerts@netflix.com\r\nSubject: New season\r\nDate: Fri, 7 Nov 2026 10:00:00 +0000\r\n\r\nWatch now".utf8)),
            Message(uid: 2, raw: Array("Message-ID: <d2@x.t>\r\nFrom: receipt@amzn.com\r\nSubject: Your order shipped\r\nDate: Fri, 7 Nov 2026 11:00:00 +0000\r\n\r\nOn the way".utf8)),
            Message(uid: 3, raw: Array("Message-ID: <d3@x.t>\r\nFrom: sarah@wave.co\r\nSubject: Re: contract\r\nDate: Fri, 7 Nov 2026 12:00:00 +0000\r\n\r\nClause 4 updated".utf8)),
            Message(uid: 4, raw: Array("Message-ID: <d4@x.t>\r\nFrom: stranger@unknown.co\r\nSubject: hello?\r\nDate: Fri, 7 Nov 2026 13:00:00 +0000\r\n\r\nfirst time".utf8)),
        ])])
        try? model.syncAndClassify(transport: server)
        return model
    }
}
