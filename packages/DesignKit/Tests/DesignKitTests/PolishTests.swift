import AuthKit
import CoreKit
import Foundation
import MailProtoKit
import MirrorKit
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（批次 4：DESIGN-002/003/004 · JOURNEY-016）

@MainActor
struct PolishTests {

    // MARK: - DESIGN-002 token 全集与内联色清零

    @Test("DESIGN-002 token 全集与规范一致；视图层零内联色/字号")
    func design_002_full_token_set() throws {
        // 形状与动效（§4/§6）
        #expect(DesignTokens.radiusWindow == 14)
        #expect(DesignTokens.radiusCard == 8)
        #expect(DesignTokens.radiusButton == 10)
        #expect(DesignTokens.radiusSearch == 8)
        #expect(DesignTokens.avatarSize == 26)
        #expect(DesignTokens.readerAvatarSize == 26)
        #expect(DesignTokens.readingMeasure == 600)
        #expect(DesignTokens.rowHeight == 98)
        #expect(DesignTokens.Motion.micro == 0.12)
        #expect(DesignTokens.Motion.transition == 0.22)
        #expect(DesignTokens.Motion.classification == 0.32)
        #expect(DesignTokens.Motion.classificationSpringResponse == 0.32)
        #expect(DesignTokens.Motion.classificationSpringDamping == 0.86)
        #expect(DesignTokens.Motion.readerOffset(reduceMotion: false) == 6)
        #expect(DesignTokens.Motion.readerOffset(reduceMotion: true) == 0)

        // Inbox Reference 浅色角色（§2）；双主题完整解析由 DESIGN-005 锁定
        #expect(DesignTokens.brandBlueBorderHex == 0xB8DDF3)
        #expect(DesignTokens.surfaceWashHex == 0xF4F7F9)
        #expect(DesignTokens.borderHairlineHex == 0xE8EEF2)
        #expect(DesignTokens.statusSuccessBgHex == 0xE7F5EC)
        #expect(DesignTokens.statusSuccessFgHex == 0x237A46)
        #expect(DesignTokens.inkBodyHex == 0x2C3E4B)

        // 源码扫描：视图层禁止内联 Color(red:) 与 .font(.system(size:))（DesignTokens 除外）
        let violations = try Self.scanSources()
        #expect(violations.isEmpty, "发现绕过 token 的内联样式：\(violations)")
    }

    /// 源码防漂移扫描：#filePath 相对定位 Sources 目录。
    static func scanSources() throws -> [String] {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourcesDir = testFile.deletingLastPathComponent() // Tests/DesignKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DesignKit
            .appendingPathComponent("Sources/DesignKit")
        guard FileManager.default.fileExists(atPath: sourcesDir.path) else { return [] }
        var violations: [String] = []
        let enumerator = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  !url.lastPathComponent.isEmpty,
                  url.lastPathComponent != "DesignTokens.swift", // token 定义本体
                  url.lastPathComponent != "MailDateIndex.swift" else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (number, line) in content.components(separatedBy: "\n").enumerated() {
                if line.contains("Color(red:") {
                    violations.append("\(url.lastPathComponent):\(number + 1) 内联 Color(red:…)")
                }
                if line.contains(".font(.system(size:") {
                    violations.append("\(url.lastPathComponent):\(number + 1) 内联字号 .font(.system(size:…)")
                }
            }
        }
        return violations
    }

    @Test("DESIGN-002 原图邮件表面与阴影参数")
    func design_002_mail_elevation_spec() {
        #expect(MailElevationSpec.headerRadius == 6 && MailElevationSpec.headerY == 3)
        #expect(MailElevationSpec.rowRadius == 6 && MailElevationSpec.rowY == 3)
        #expect(MailElevationSpec.selectedRadius == 14 && MailElevationSpec.selectedY == 4)
        #expect(MailElevationSpec.paneRadius == 12 && MailElevationSpec.paneX == 4)
        #expect(MailElevationSpec.headerOpacity == 0.06)
        #expect(MailElevationSpec.rowOpacity == 0.06)
        #expect(MailElevationSpec.selectedOpacity == 0.12)
        #expect(MailElevationSpec.paneOpacity == 0.10)
    }

    // MARK: - DESIGN-003 多语言

    @Test("DESIGN-003 en/zh-Hans 双语齐备、键位对齐、未知语言回落 en")
    func design_003_localization() throws {
        #expect(L10n.availableLanguages.contains("en"))
        // CI 工具链可能把 lproj 规范为小写 zh-hans（实测），大小写不敏感断言
        #expect(L10n.availableLanguages.contains { $0.caseInsensitiveCompare("zh-Hans") == .orderedSame })

        // 双语取词
        #expect(L10n.t("segment.new", languageCode: "en") == "New")
        #expect(L10n.t("segment.new", languageCode: "zh-Hans") == "新邮件")
        #expect(L10n.t("segment.seen", languageCode: "en") == "Previously seen")
        #expect(L10n.t("segment.aside", languageCode: "zh-Hans") == "暂缓处理")
        #expect(L10n.t("bucket.paperTrail", languageCode: "zh-Hans") == "Paper Trail", "桶名 hey 式造词保留原文")
        #expect(L10n.t("privacy.ondevice", languageCode: "zh-Hans").contains("本机"))

        // 未知语言回落 en
        #expect(L10n.t("segment.new", languageCode: "fr-FR") == "New")

        // 键位对齐：两个 strings 表键集合一致（源文件级）
        let enKeys = try Self.stringKeys(language: "en")
        let zhKeys = try Self.stringKeys(language: "zh-Hans")
        #expect(!enKeys.isEmpty, "en 表应有键")
        #expect(Set(enKeys) == Set(zhKeys), "en/zh-Hans 键位不对齐：\(Set(enKeys).symmetricDifference(Set(zhKeys)))")
    }

    static func stringKeys(language: String) throws -> [String] {
        let testFile = URL(fileURLWithPath: #filePath)
        let path = testFile.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignKit/Resources/\(language).lproj/Localizable.strings")
        let content = try String(contentsOf: path, encoding: .utf8)
        return content.components(separatedBy: "\n")
            .compactMap { line in
                guard line.hasPrefix("\""), let eq = line.firstIndex(of: "=") else { return nil }
                return String(line[line.index(after: line.startIndex)..<line.index(before: eq)]).trimmingCharacters(in: .whitespaces)
            }
    }

    // MARK: - DESIGN-004 动效

    @Test("DESIGN-004 动效 token 与减弱动态降级")
    func design_004_motion_tokens() {
        #expect(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro, reduceMotion: false) != nil)
        #expect(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro, reduceMotion: true) == nil,
                "减弱动态 → 无动画")
        #expect(DesignTokens.Motion.spring(reduceMotion: true) == nil)
        #expect(DesignTokens.Motion.spring(reduceMotion: false) != nil)
    }

    // MARK: - JOURNEY-016 Settings（断开连接闭环）

    @Test("JOURNEY-016 断开连接：清凭证与账户记录、回账户页")
    func journey_016_settings_scene() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailo-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vault = AuthKit.InMemoryVault()
        try vault.save("secret-token", for: "mailo.acct.outlook.u@t")

        // 已连接状态
        let server = FakeImapServer(mailboxes: ["INBOX": .init(uidValidity: 4, messages: [
            Message(uid: 1, raw: Array("Message-ID: <s1@x>\r\nFrom: a@b.co\r\nSubject: s\r\n\r\nbody".utf8)),
        ])])
        let model = MailoAppModel(store: try MirrorStore(), pipeline: ClassificationPipeline())
        let account = AccountConfig(displayName: "t", imapHost: "h", smtpHost: "s",
                                    username: "u@t", secretRef: "mailo.acct.outlook.u@t")
        try await model.attach(account: account, transport: server)
        model.startPolling()
        let accounts = AccountStore(directory: dir)
        try accounts.save(AccountRecord(email: "u@t", clientId: "cid",
                                        accountKind: .personal, secretRef: account.secretRef))
        guard case .connected = model.phase else {
            Issue.record("前置：应已连接")
            return
        }

        // 断开
        model.disconnect(vault: vault, directory: dir)

        #expect(model.phase == .empty, "回账户页")
        #expect(AccountStore(directory: dir).loadPrimary() == nil, "账户记录清除")
        #expect(try vault.load(account.secretRef) == nil, "Keychain 凭证随删")
        #expect(!model.isSyncCapable, "轮询已停（runner 清空）")
        #expect(model.entries.isEmpty)
    }
}
