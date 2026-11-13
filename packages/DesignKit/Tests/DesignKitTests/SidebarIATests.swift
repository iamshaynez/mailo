import Testing
import CoreKit
import Foundation

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-025 侧栏信息架构 v2）

struct SidebarIATests {

    @Test("JOURNEY-025 侧栏 IA v2：Screener 置顶 → 三桶 → Set Aside；零假项")
    func journey_025_sidebar_ia_v2() {
        let items = SidebarIA.items(
            bucketCounts: ["imbox": 3, "feed": 2, "paperTrail": 1, "screener": 4, "setAside": 0],
            isDemo: true, canCompose: true, isSyncCapable: true, showsSettings: true)

        // 桶顺序严格：Screener → Imbox/Feed/Paper Trail（可展开）→ Set Aside；blocked 永不出现
        let buckets = items.compactMap { entry -> Bucket? in
            guard case let .bucket(b, _, _) = entry else { return nil }
            return b
        }
        #expect(buckets == [.screener, .imbox, .feed, .paperTrail, .setAside])

        // 计数来自真实 bucketCounts
        func count(_ b: Bucket) -> Int {
            items.first { if case let .bucket(x, c, _) = $0 { return x == b } else { return false } }
                .map { if case let .bucket(_, c, _) = $0 { return c } else { return -1 } } ?? -1
        }
        #expect(count(.screener) == 4)
        #expect(count(.setAside) == 0)

        // 三桶可展开组列表，Screener/Set Aside 不展开
        #expect(items.contains { if case .bucket(.feed, 2, true) = $0 { return true } else { return false } })
        #expect(items.contains { if case .bucket(.screener, 4, false) = $0 { return true } else { return false } })

        // 分隔线：Screener 后、Set Aside 前各一条
        #expect(items.first == .bucket(.screener, count: 4, expandable: false))
        #expect(items.filter { $0 == .separator }.count == 2)

        // 底部动作组：写邮件 / 设置 / 立即同步 / 退出 Demo（demo 时）
        guard case .compose(true)? = items.last(where: { if case .compose = $0 { return true } else { return false } })
        else { Issue.record("compose entry missing"); return }
        #expect(items.contains(.settings))
        #expect(items.contains(.syncNow(enabled: true)))
        #expect(items.contains(.exitDemo))

        // 非 demo：不出现退出 Demo；同步不可用时禁用
        let plain = SidebarIA.items(bucketCounts: [:], isDemo: false,
                                    canCompose: false, isSyncCapable: false, showsSettings: false)
        #expect(!plain.contains(.exitDemo))
        #expect(!plain.contains(.settings))
        #expect(plain.contains(.syncNow(enabled: false)))
        #expect(plain.contains(.compose(enabled: false)))
    }

    @Test("JOURNEY-025 底部动作与导航分组，供视图在两者之间插入弹性留白")
    func journey_025_sidebar_actions_stay_at_bottom() {
        let arguments = (bucketCounts: ["screener": 626, "setAside": 1],
                         isDemo: true, canCompose: true, isSyncCapable: true, showsSettings: true)
        let sections = SidebarIA.sections(
            bucketCounts: arguments.bucketCounts, isDemo: arguments.isDemo,
            canCompose: arguments.canCompose, isSyncCapable: arguments.isSyncCapable,
            showsSettings: arguments.showsSettings)
        let flat = SidebarIA.items(
            bucketCounts: arguments.bucketCounts, isDemo: arguments.isDemo,
            canCompose: arguments.canCompose, isSyncCapable: arguments.isSyncCapable,
            showsSettings: arguments.showsSettings)

        #expect(sections.navigation + sections.actions == flat)
        #expect(sections.navigation.last == .bucket(.setAside, count: 1, expandable: false))
        #expect(sections.actions == [
            .compose(enabled: true), .settings, .syncNow(enabled: true), .exitDemo,
        ])
    }

    @Test("JOURNEY-025 零假项：假导航键与无动作槽位从代码与文案中清除")
    func journey_025_no_fake_nav_items() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DesignKitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // DesignKit/
            .appendingPathComponent("Sources/DesignKit")

        let sidebar = try String(contentsOf: sources.appendingPathComponent("SidebarView.swift"), encoding: .utf8)
        for fake in ["nav.chat", "nav.spaces", "nav.call", "nav.starred",
                     "nav.snoozed", "nav.sent", "nav.draft", "nav.labels", "nav.more"] {
            #expect(!sidebar.contains(fake), "侧栏不得再引用假导航键 \(fake)")
        }

        for lang in ["en", "zh-Hans"] {
            let strings = try String(contentsOf: sources
                .appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
            for fake in ["nav.chat", "nav.spaces", "nav.call", "nav.starred",
                         "nav.snoozed", "nav.sent", "nav.draft", "nav.labels", "nav.more"] {
                #expect(!strings.contains(fake), "\(lang) 文案不得再定义假导航键 \(fake)")
            }
        }
    }
}
