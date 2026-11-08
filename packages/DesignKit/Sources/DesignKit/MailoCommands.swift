import CoreKit
import MirrorKit
import SwiftUI

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-008 / JOURNEY-009 · 批次 2 扩充）

/// UI 意图（JOURNEY-009）：菜单/快捷键 → 壳层动作的唯一通道。
/// Commands 场景在 App 壳里，动作目标（sheet/焦点/选中）在 MailoShell 里，
/// 经 model 广播、由壳消费——避免跨 Scene 状态穿透。
public enum MailoUICommand: Equatable, Sendable {
    /// ⌘N：新邮件（打开撰写）
    case compose
    /// ⌘K：聚焦搜索框
    case focusSearch
    /// ⌘R：回复当前阅读邮件（JOURNEY-011）
    case reply
    /// ⌘⇧F：转发（JOURNEY-011）
    case forward
    /// ⌘S：Set Aside（JOURNEY-012）
    case setAside
    /// ⌘⇧U：标未读/已读切换（JOURNEY-013）
    case toggleUnread
}

/// 命令请求（单调递增 id：同一命令重复触发也能被 onChange 观察）。
public struct MailCommandRequest: Equatable, Sendable {
    public let id: Int
    public let command: MailoUICommand

    init(id: Int, command: MailoUICommand) {
        self.id = id
        self.command = command
    }
}

/// 菜单可用性矩阵（JOURNEY-009）：邮件动作要求「有选中且处于阅读态」。
/// 纯函数：菜单打开时求值，测试直接锁行为。
public struct MailCommandAvailability: Equatable, Sendable {
    public let canReply: Bool
    public let canForward: Bool
    public let canAct: Bool
    public let canSetAside: Bool
    public let canToggleUnread: Bool

    public init(selection: String?, isReading: Bool) {
        let ready = selection != nil && isReading
        canReply = ready
        canForward = ready
        canAct = ready
        canSetAside = ready
        canToggleUnread = ready
    }
}

/// 列表 selection 桥接（JOURNEY-008）：stableId 即 List 的 tag；
/// ↑↓ 键盘导航的邻位计算与视觉顺序一致（当前列表过滤后顺序）。
public struct MailSelectionBridge: Equatable, Sendable {
    public let entries: [BucketEntry]

    public init(entries: [BucketEntry]) {
        self.entries = entries
    }

    public var tags: [String] { entries.map(\.stableId) }

    public func next(after tag: String) -> String? {
        neighbor(tag, offset: 1)
    }

    public func previous(before tag: String) -> String? {
        neighbor(tag, offset: -1)
    }

    private func neighbor(_ tag: String, offset: Int) -> String? {
        let tags = self.tags
        guard let index = tags.firstIndex(of: tag) else { return tags.first }
        let target = tags.index(index, offsetBy: offset)
        return tags.indices.contains(target) ? tags[target] : nil
    }
}

/// App 壳挂载的命令面（JOURNEY-009）：MailoMac/MailoIOS 的 `.commands` 直接复用。
/// 菜单项在打开时求值 disabled——root.active 按引用读取，demo/真实切换即时生效。
public struct MailoCommandMenu: Commands {
    let root: MailoRootModel

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Message") { model.request(.compose) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.canCompose)
        }
        CommandMenu("Message") {
            Button("Search") { model.request(.focusSearch) }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Reply") { model.request(.reply) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!availability.canReply)
            Button("Forward") { model.request(.forward) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!availability.canForward)
            Button("Set Aside") { model.request(.setAside) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!availability.canSetAside)
            Divider()
            Button("Mark Unread") { model.request(.toggleUnread) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!availability.canToggleUnread)
            Divider()
            Button("Sync Now") { model.syncNow() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.isSyncCapable)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model.lastAction.map { "Undo \($0.label)" } ?? "Undo") { model.undoLast() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.lastAction == nil)
        }
    }

    private var model: MailoAppModel { root.active }

    private var availability: MailCommandAvailability {
        MailCommandAvailability(selection: model.readingStableId, isReading: model.readingStableId != nil)
    }
}
