import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 参考图 Demo 素材（DESIGN-007）；仅由演示邮件使用，不读取真实账户资源。
enum ReferenceDemoAssets {
    private static let avatarNames = [
        "penny@reference.demo": "penny",
        "fakri@reference.demo": "fakri",
        "john@reference.demo": "john",
        "musi@reference.demo": "musi",
        "pooja@reference.demo": "pooja",
        "neha@reference.demo": "neha",
    ]

    static func avatar(for rawAddress: String?) -> Image? {
        guard let name = avatarNames[SenderPresentation(rawAddress).address.lowercased()] else { return nil }
        return image(named: name)
    }

    static func data(named name: String) -> Data? {
        guard let url = resourceURL(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func image(named name: String) -> Image? {
        guard let data = data(named: name) else { return nil }
        #if canImport(AppKit)
        return NSImage(data: data).map(Image.init(nsImage:))
        #elseif canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #else
        return nil
        #endif
    }

    private static func resourceURL(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "ReferenceDemo")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
    }
}

public extension MailoAppModel {
    /// 完整参考图 Demo（DESIGN-007/JOURNEY-010）：独立内存库、六封邮件与真实图片 MIME 附件。
    @MainActor
    static func bootstrapReferenceDemo() async -> MailoAppModel {
        let store = (try? MirrorStore()) ?? MirrorStore.unavailableForReferenceDemo()
        let model = MailoAppModel(
            store: store,
            pipeline: ClassificationPipeline(roster: Roster(domainBuckets: ["reference.demo": .imbox])))
        let fixture = ReferenceDemoFixture()
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 42, messages: fixture.messages)])
        let account = AccountConfig(displayName: "Demo", imapHost: "demo.local", smtpHost: "demo.local",
                                    username: "demo@local", secretRef: "demo")
        try? await model.attach(account: account, transport: server)
        fixture.applySnippets(to: store)
        fixture.applyDemoGroups(to: model) // JOURNEY-026：演示桶内组即刻可见
        try? model.load(bucket: .imbox)
        model.activateDemoPhase()
        return model
    }
}

private extension MirrorStore {
    static func unavailableForReferenceDemo() -> MirrorStore {
        fatalError("in-memory MirrorStore cannot fail")
    }
}

/// 内容只服务视觉验收；普通 bootstrapDemo 的协议测试数据不受影响。
private struct ReferenceDemoFixture {
    struct Item {
        let uid: Int
        let name: String
        let local: String
        let subject: String
        let snippet: String
        let date: String
        let read: Bool
    }

    let items = [
        Item(uid: 1, name: "Penny Singh", local: "penny", subject: "Product Design on Client Base",
             snippet: "If they've never received communication from you, tell them a bit about yourself in a way that's warm and authentic.",
             date: "Mon, 9 Nov 2026 10:10:00 +0800", read: false),
        Item(uid: 2, name: "Fakri Josh", local: "fakri", subject: "Thanks for registering as a contributor!",
             snippet: "It's great to have you here! We're ready to make the most of our time together, but there's one more step you need to follow before uploading your content to. Let's get you started!",
             date: "Mon, 9 Nov 2026 09:15:00 +0800", read: false),
        Item(uid: 3, name: "John Appendix", local: "john", subject: "Visual Design vs. Graphic Design: Which Career is for You?",
             snippet: "Today on the blog, discover a list of critical tools that every designer needs to grow their business in 2023 and beyond. From lead capture and management to automation.",
             date: "Mon, 9 Nov 2026 08:30:00 +0800", read: false),
        Item(uid: 4, name: "Musi Dabara", local: "musi", subject: "Let's Make Some Music – Your Uplabs Design Updates Have Landed",
             snippet: "This week's challenge will be music to your ears! This week, we challenge you to create your very own version of this subscription-based app for music.",
             date: "Mon, 9 Nov 2026 07:20:00 +0800", read: false),
        Item(uid: 5, name: "Pooja Dutt", local: "pooja", subject: "Unlock discounts with every purchase this month",
             snippet: "To qualify, purchases must be made between Dec 7–31, 2022. Your discount coupon will be sent via email and available for use on January 2023.",
             date: "Mon, 9 Nov 2026 06:11:00 +0800", read: true),
        Item(uid: 6, name: "Neha Kakkar", local: "neha", subject: "Merhaba and Seasons Greetings from the Zeplin",
             snippet: "Merhaba and Seasons Greetings from the Zeplin crew to you! We're quickly approaching the end of 2022, and it's been one incredible journey.",
             date: "Sun, 8 Nov 2026 16:00:00 +0800", read: true),
    ]

    var messages: [Message] {
        items.map { item in
            Message(uid: item.uid, flags: item.read ? ["\\Seen"] : [], raw: rawMessage(item))
        }
    }

    func applySnippets(to store: MirrorStore) {
        guard let entries = try? store.entries(bucket: .imbox) else { return }
        for entry in entries {
            guard var row = try? store.mail(stableId: entry.stableId),
                  let item = items.first(where: { entry.subject == $0.subject }) else { continue }
            row.snippet = item.snippet
            try? store.upsert(row)
        }
    }

    /// Demo 桶内组（JOURNEY-026）：给六封示例邮件归入三个组，侧栏组列表即刻真实可点。
    @MainActor
    func applyDemoGroups(to model: MailoAppModel) {
        let groups: [String: MailTag] = [
            "penny": MailTag("设计"), "john": MailTag("设计"),
            "fakri": MailTag("产品"), "musi": MailTag("产品"),
            "pooja": MailTag("营销"), "neha": MailTag("营销"),
        ]
        guard let entries = try? model.store.entries(bucket: .imbox) else { return }
        for entry in entries {
            let address = SenderPresentation(entry.fromAddress).address.lowercased()
            guard let tag = groups.first(where: { address.hasPrefix("\($0.key)@") })?.value else { continue }
            try? model.assignTag(stableId: entry.stableId, tag: tag)
        }
    }

    private func rawMessage(_ item: Item) -> [UInt8] {
        let headers = "Message-ID: <reference-\(item.uid)@mailo.demo>\r\nFrom: \(item.name) <\(item.local)@reference.demo>\r\nTo: you@demo.local\r\nSubject: \(item.subject)\r\nDate: \(item.date)\r\n"
        if item.local != "john" {
            return Array((headers + "\r\n" + item.snippet).utf8)
        }

        let boundary = "mailo-reference-boundary"
        let text = "Hello Bagdad,\n\nMerhaba and Seasons Greetings from the Zeplin crew to you! We're quickly approaching the end of 2022, and it's been one incredible journey.\n\nWhat's kept us inspired along the way is the stories we've heard from PMs, designers, and developers who rely on Zeplin to organize design screens, sync their design and development teams, and so much more.\n\nSo whether you're a longtime user or new to Zeplin, explore our product features that tap into new use cases and address common workflow challenges.\n\nBest regards,"
        var raw = headers + "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n--\(boundary)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(text)\r\n"
        for index in 1...3 {
            guard let data = ReferenceDemoAssets.data(named: "attachment-\(index)") else { continue }
            raw += "--\(boundary)\r\nContent-Type: image/png; name=\"reference-\(index).png\"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename=\"reference-\(index).png\"\r\n\r\n"
            raw += data.base64EncodedString() + "\r\n"
        }
        raw += "--\(boundary)--\r\n"
        return Array(raw.utf8)
    }
}
