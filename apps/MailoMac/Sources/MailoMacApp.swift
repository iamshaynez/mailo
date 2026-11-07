import DesignKit
import SwiftUI

@main
struct MailoMacApp: App {
    @StateObject private var model = MailoAppModel.bootstrapDemo()

    var body: some Scene {
        WindowGroup {
            MailoShell(model: model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
    }

    /// 菜单栏常驻（基线 §7：macOS 常驻进程天然在线——M1 接 IDLE 后挂同步入口）。
    private struct MenuBarPlaceholder: View {
        var body: some View { Image(systemName: "envelope") }
    }
}
