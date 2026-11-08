import AuthKit
import DesignKit
import SwiftUI

@main
struct MailoIOSApp: App {
    @StateObject private var root = MailoRootModel(live: MailoAppModel.createLive())

    var body: some Scene {
        WindowGroup {
            MailoShell(root: root)
                .task {
                    // 启动恢复上次会话（JOURNEY-005）：refresh token 免设备码；失败留在欢迎页
                    if case .empty = root.live.phase {
                        _ = await root.live.restoreSavedAccount(vault: KeychainVault())
                    }
                }
        }
        .commands { MailoCommandMenu(root: root) }
    }
}
