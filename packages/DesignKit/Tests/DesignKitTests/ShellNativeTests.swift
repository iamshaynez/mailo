import CoreKit
import MailProtoKit
import MirrorKit
import SwiftUI
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-008 / JOURNEY-009）

/// 骨架原生化（NavigationSplitView + List 键盘选择 + 菜单快捷键）。
/// 视觉骨架用 NSHostingView 离屏冒烟（可渲染、不崩溃）；
/// 可测内核抽取为 CommandRouter（意图路由）、MailSelectionBridge（List selection ↔ stableId）
/// 与 MailCommandAvailability（菜单可用性）。
@MainActor
struct ShellNativeTests {

    // MARK: - JOURNEY-008

    @Test("JOURNEY-008 三栏壳可离屏渲染（NavigationSplitView 骨架冒烟）")
    func journey_008_splitview_skeleton() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        let shell = MailoShell(model: model)
        #if os(macOS)
        let host = NSHostingView(rootView: shell)
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        host.layoutSubtreeIfNeeded()
        #endif
        #expect(model.phase == .demo)
        #expect(!model.entries.isEmpty, "demo 装配后列表非空")
    }

    @Test("JOURNEY-008 HTML 阅读态在固定尺寸三栏壳中离屏渲染")
    func journey_008_html_reader_fixed_size() async throws {
        #if os(macOS)
        let model = await MailoAppModel.bootstrapDemo()
        let stableID = StableMessageID(messageId: "<html-layout@x>", accountFingerprint: "demo")
        let html = "Message-ID: <html-layout@x>\r\nFrom: layout@x.co\r\nSubject: HTML layout\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<div style=\"color:#18202B\"><h1>Layout</h1><p>Body</p></div>"
        try await model.apply([MailEvent(stableMessageID: stableID, uid: 99, flags: [],
                                        raw: Array(html.utf8), subject: "HTML layout",
                                        fromAddress: "layout@x.co")])
        try model.load(bucket: .screener)

        let host = NSHostingView(rootView: MailoShell(model: model, initialSelection: stableID.value))
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()

        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        #expect(image.size.width == 1280 && image.size.height == 820)
        if ProcessInfo.processInfo.environment["MAILO_CAPTURE"] != nil {
            try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/mailo-shell-html.png"))
        }
        #endif
    }

    @Test("JOURNEY-008 列表 selection 桥接：stableId 即 tag，↑↓ 邻位移动")
    func journey_008_selection_bridge_tags() {
        let bridge = MailSelectionBridge(entries: [
            BucketEntry(stableId: "a", bucket: "imbox"),
            BucketEntry(stableId: "b", bucket: "imbox"),
        ])
        #expect(bridge.tags == ["a", "b"])
        #expect(bridge.next(after: "a") == "b")
        #expect(bridge.next(after: "b") == nil)
        #expect(bridge.previous(before: "b") == "a")
        #expect(bridge.previous(before: "a") == nil)
    }

    // MARK: - JOURNEY-009

    @Test("JOURNEY-009 命令路由：菜单动作 → 单调递增请求")
    func journey_009_menu_shortcuts() {
        let model = MailoAppModel(
            store: (try? MirrorStore()) ?? MirrorStore.unavailable(),
            pipeline: ClassificationPipeline())

        var ids: [Int] = []
        model.request(.compose)
        ids.append(model.commandRequest?.id ?? -1)
        model.request(.focusSearch)
        ids.append(model.commandRequest?.id ?? -1)
        model.request(.compose)
        ids.append(model.commandRequest?.id ?? -1)

        #expect(ids == ids.sorted(), "请求 id 单调递增（同一命令重复触发也生效）")
        #expect(model.commandRequest?.command == .compose)
    }

    @Test("JOURNEY-009 命令可用性：无选中/非阅读态时回复转发 Set Aside 禁用")
    func journey_009_command_availability() {
        #expect(!MailCommandAvailability(selection: nil, isReading: false).canReply)
        #expect(!MailCommandAvailability(selection: "x", isReading: false).canAct)
        let reading = MailCommandAvailability(selection: "x", isReading: true)
        #expect(reading.canReply && reading.canForward && reading.canAct)
    }

    @Test("JOURNEY-009 手动同步可用性随连接状态")
    func journey_009_sync_availability() async throws {
        let model = MailoAppModel(
            store: try MirrorStore(),
            pipeline: ClassificationPipeline())
        #expect(!model.isSyncCapable, "未连接不可手动同步")
        let demo = await MailoAppModel.bootstrapDemo()
        #expect(demo.isSyncCapable, "demo 装配后可手动同步")
    }
}

extension MirrorStore {
    /// 测试兜底：内存库构造不应失败；此方法让调用点保持表达式形态。
    static func unavailable() -> MirrorStore {
        fatalError("in-memory MirrorStore cannot fail")
    }
}
