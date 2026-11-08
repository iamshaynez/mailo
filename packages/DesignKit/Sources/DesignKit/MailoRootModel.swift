import CoreKit
import Foundation
import MirrorKit
import SwiftUI

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-010 Demo 隔离）

/// App 根模型：持有「真实账户模型」与可选的「Demo 模型」两条装配。
/// Demo 走独立内存库（`bootstrapDemo()` 无 store 参数即 in-memory），永不触碰生产
/// `mailo.sqlite`；退出即丢弃。壳层渲染 `active`（demo 优先），并常驻 Demo 水印。
@MainActor
public final class MailoRootModel: ObservableObject {
    @Published public private(set) var demo: MailoAppModel?
    public let live: MailoAppModel

    /// 撰写会话（macOS 独立窗口 / iOS sheet 共享的草稿状态）。
    @Published public var composeDraft: ComposeDraft?

    public init(live: MailoAppModel) {
        self.live = live
    }

    /// 当前渲染的数据源（Demo 模式优先）。
    public var active: MailoAppModel { demo ?? live }

    /// 进入 Demo（JOURNEY-010）：独立内存库装配，不动 live 的任何状态。
    public func enterDemo() {
        Task { await enterDemoAndWait() }
    }

    /// 可测入口：装配完成才返回。
    public func enterDemoAndWait() async {
        guard demo == nil else { return }
        demo = await MailoAppModel.bootstrapDemo() // 无 store 参数 → 独立内存库
    }

    /// 退出 Demo：丢弃内存库与模型，回到 live（账户页或已连接状态）。
    public func exitDemo() {
        demo = nil
    }
}
