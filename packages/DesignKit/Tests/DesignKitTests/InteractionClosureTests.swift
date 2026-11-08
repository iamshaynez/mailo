import CoreKit
import MailProtoKit
import MirrorKit
import SwiftUI
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（批次 2 交互闭环）

@MainActor
struct InteractionClosureTests {

    // MARK: - JOURNEY-010 Demo 隔离

    @Test("JOURNEY-010 Demo 独立内存库装配、可退出、不触碰生产库")
    func journey_010_demo_isolation() async throws {
        // 生产库：文件库含 1 封已入库邮件
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailo-test-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let liveStore = try MirrorStore(path: tmp)
        try liveStore.upsert(MailRow(stableId: "real-1", account: "primary", folder: "INBOX",
                                     uid: 1, flags: [], subject: "real"))
        try liveStore.freeze(ClassificationRow(stableId: "real-1", bucket: .imbox, reason: "t"))
        let live = MailoAppModel(store: liveStore, pipeline: ClassificationPipeline())
        let root = MailoRootModel(live: live)

        await root.enterDemoAndWait()
        let demo = try #require(root.demo)
        #expect(demo.store !== liveStore, "demo 必须装配独立内存库")
        #expect(root.active === demo)
        #expect(demo.phase == .demo)
        #expect(demo.entries.isEmpty == false, "demo 自带样例邮件")
        #expect(try liveStore.entries(bucket: .imbox).count == 1, "生产库不被 demo 写入")

        root.exitDemo()
        #expect(root.demo == nil)
        #expect(root.active === live)
    }

    // MARK: - JOURNEY-011 Reply / Forward 预填

    @Test("JOURNEY-011 Reply/Forward 预填：收件人、主题前缀、引用正文")
    func journey_011_reply_forward_prefill() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        try model.load(bucket: .imbox)
        let target = try #require(model.entries.first { $0.fromAddress == "sarah@wave.co" })

        // Reply 发生在邮件已打开之后：阅读窗格的 mailDetail 已回填 raw（SYNC-014 两段式）
        _ = model.mailDetail(stableId: target.stableId)

        let reply = try #require(model.composeDraft(for: target.stableId, kind: .reply))
        #expect(reply.to == "sarah@wave.co")
        #expect(reply.subject == "Re: contract", "已有 Re: 前缀不重复叠加")
        #expect(reply.body.contains("> Clause 4 updated"), "引用原邮件正文")

        let forward = try #require(model.composeDraft(for: target.stableId, kind: .forward))
        #expect(forward.subject == "Fwd: Re: contract")
        #expect(forward.to.isEmpty, "转发不预填收件人")
        #expect(forward.body.contains("Clause 4 updated"))

        // 无主题邮件的兜底
        #expect(ComposeDraft.replySubject(nil) == "Re: (no subject)")
    }

    // MARK: - JOURNEY-012 Set Aside

    @Test("JOURNEY-012 Set Aside：桶迁移、计数联动、⌘Z 撤销")
    func journey_012_set_aside() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        try model.load(bucket: .imbox)
        let target = try #require(model.entries.first)
        let stableId = target.stableId

        try model.setAside(stableId: stableId)
        #expect(model.entries.isEmpty, "imbox 列表移除该行")
        #expect(model.bucketCounts[Bucket.setAside.rawValue] == 1)
        try model.load(bucket: .setAside)
        #expect(model.entries.map(\.stableId) == [stableId])

        // 撤销：回到原桶
        model.undoLast()
        try model.load(bucket: .setAside)
        #expect(model.entries.isEmpty)
        try model.load(bucket: .imbox)
        #expect(model.entries.map(\.stableId) == [stableId])
        #expect(model.lastAction == nil, "撤销栈清空")
    }

    // MARK: - JOURNEY-013 打开即已读（本地 + 服务器写回）

    @Test("JOURNEY-013 markRead：本地 flags 并入 \\Seen + UID STORE 写回假服务器")
    func journey_013_mark_seen_on_open() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        try model.load(bucket: .imbox)
        let target = try #require(model.entries.first { !$0.flags.contains("\\Seen") })
        let stableId = target.stableId

        // 打开即读：本地立即生效（未读点消失路径）
        model.markRead(stableId: stableId)
        guard let row = try? model.store.mail(stableId: stableId) else {
            Issue.record("row should exist")
            return
        }
        #expect(row.flagList.contains("\\Seen"))
        try model.load(bucket: .imbox)
        #expect(model.entries.first { $0.stableId == stableId }?.flags.contains("\\Seen") == true)

        // 服务器写回（尽力而为，独立入口可测）
        try model.storeSeenOnServer(stableId: stableId)
        let uid = row.uid
        let serverFlags = model.runnerDebugTransport.map { transport -> [String]? in
            (transport as? FakeImapServer)?.mailboxes["INBOX"]?.messages
                .first { $0.uid == uid }?.flags.sorted()
        } ?? nil
        #expect(serverFlags?.contains("\\Seen") == true)

        // 重复 markRead 幂等，不重复追加
        model.markRead(stableId: stableId)
        #expect(try model.store.mail(stableId: stableId)?.flagList.filter { $0 == "\\Seen" }.count == 1)
    }

    // MARK: - JOURNEY-017 手动纠正常驻入口

    @Test("JOURNEY-017 reclassify：显式规则 + 同发件人待定件全部迁移")
    func journey_017_manual_correction_entry() async throws {
        // 两位陌生发件人各一封 → 都进 Screener
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: [
            Message(uid: 1, raw: Array("Message-ID: <c1@x>\r\nFrom: a@strange.co\r\nSubject: one\r\n\r\nfirst".utf8)),
            Message(uid: 2, raw: Array("Message-ID: <c2@x>\r\nFrom: a@strange.co\r\nSubject: two\r\n\r\nsecond".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(),
                                  pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "t", smtpHost: "t",
                                    username: "u@t", secretRef: "s")
        try await model.attach(account: account, transport: server)
        try model.load(bucket: .screener)
        #expect(model.entries.count == 2)

        // 纠正第一封 → imbox：规则生成，同发件人两封全部迁移
        let first = try #require(model.entries.first { $0.subject == "one" })
        try model.reclassify(stableId: first.stableId, to: .imbox)

        #expect(model.pipeline.rules.contains {
            $0.matcher == .senderExact("a@strange.co") && $0.bucket == .imbox
        })
        try model.load(bucket: .screener)
        #expect(model.entries.isEmpty, "同发件人待定件随规则全部迁移")
        try model.load(bucket: .imbox)
        #expect(model.entries.count == 2)

        // 下一封同发件人直接命中规则（管线视角）
        let signal = MailSignal(messageID: StableMessageID(messageId: "<c3@x>", accountFingerprint: "primary"),
                                senderLocalPart: "a", senderDomain: "strange.co", subject: "three")
        guard case .classified(.imbox, .userRule) = model.pipeline.decide(signal) else {
            Issue.record("后续邮件应直接命中显式规则")
            return
        }
    }

    // MARK: - Block（CLS-011 的装配层行为）

    @Test("CLS-011 Block：生成规则 + blocked 桶 + Screener 计数消减")
    func cls_011_block_from_screener() async throws {
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 9, messages: [
            Message(uid: 1, raw: Array("Message-ID: <b1@x>\r\nFrom: evil@spam.co\r\nSubject: junk\r\n\r\nx".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        try await model.attach(account: AccountConfig(displayName: "t", imapHost: "t", smtpHost: "t",
                                                      username: "u@t", secretRef: "s"), transport: server)
        try model.load(bucket: .screener)
        #expect(model.screenerCount == 1)
        let target = try #require(model.entries.first)

        try model.decideScreener(stableId: target.stableId, to: .blocked)

        #expect(model.screenerCount == 0, "Block 后 Screener 计数消减")
        #expect(model.pipeline.rules.contains { $0.bucket == .blocked })
        #expect(!Bucket.navBuckets.contains(.blocked), "blocked 不出现在任何导航桶")
        try model.load(bucket: .screener)
        #expect(model.entries.isEmpty)
    }

    // MARK: - 可用性扩展

    @Test("JOURNEY-009 可用性矩阵含 Set Aside / Unread")
    func journey_009_availability_set_aside() {
        let none = MailCommandAvailability(selection: nil, isReading: false)
        #expect(!none.canSetAside && !none.canToggleUnread)
        let reading = MailCommandAvailability(selection: "x", isReading: true)
        #expect(reading.canSetAside && reading.canToggleUnread)
    }
}
