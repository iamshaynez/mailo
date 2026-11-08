import AuthKit
import DesignKit
import SwiftUI

@main
struct MailoMacApp: App {
    @StateObject private var root = MailoRootModel(live: MailoAppModel.createLive())
    @NSApplicationDelegateAdaptor(WindowAutosaveDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MailoShell(root: root)
                .task {
                    // 启动恢复上次会话（JOURNEY-005）：refresh token 免设备码；失败留在欢迎页
                    if case .empty = root.live.phase {
                        _ = await root.live.restoreSavedAccount(vault: KeychainVault())
                    }
                }
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { MailoCommandMenu(root: root) }

        // 撰写独立窗口（Mac 惯例，JOURNEY-011）：root.composeDraft 为会话状态
        Window(L10n.t("compose.title"), id: "compose") {
            ComposeWindowHost(root: root)
                .frame(minWidth: 520, minHeight: 460)
        }
        .defaultSize(width: 640, height: 520)
        .windowResizability(.contentMinSize)

        // 设置（⌘,，JOURNEY-016）
        Settings {
            MailoSettingsView(root: root)
        }
    }
}

/// 撰写窗口宿主：有草稿渲染撰写；无草稿（窗口被 ⌘W 关闭会话后残留）显示空态。
struct ComposeWindowHost: View {
    @ObservedObject var root: MailoRootModel

    var body: some View {
        if let draft = root.composeDraft {
            ComposeView(model: root.active, draft: draft, onDismiss: { root.composeDraft = nil })
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 记住主窗口位置与大小（Mac 基本品味，JOURNEY-008）：
/// SwiftUI WindowGroup 无 frame autosave 直通 API，经 NSWindow 通知挂名。
final class WindowAutosaveDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            _ = window.setFrameAutosaveName("MailoMainWindow") // 已挂名时幂等返回 false
        }
    }
}
