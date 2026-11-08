import AuthKit
import DesignKit
import SwiftUI

@main
struct MailoIOSApp: App {
    @StateObject private var model = MailoAppModel.createLive()

    var body: some Scene {
        WindowGroup {
            MailoShell(model: model)
                .task {
                    // 启动恢复上次会话（JOURNEY-005）：refresh token 免设备码；失败留在欢迎页
                    if case .empty = model.phase {
                        _ = await model.restoreSavedAccount(vault: KeychainVault())
                    }
                }
        }
        .commands { MailoCommandMenu(model: model) }
    }
}
