import AuthKit
import CoreKit
import SwiftUI

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-016 Settings 场景）

/// 设置（JOURNEY-016）：账户（断开连接）/ 隐私（远程图片默认开关）/ 诊断
/// （schema 诊断、最近同步、回填量）。macOS 由 Settings 场景承载（⌘,），
/// iOS 由侧栏隐私徽章 sheet 承载。
public struct MailoSettingsView: View {
    @ObservedObject var root: MailoRootModel
    @AppStorage("allowRemoteImages") private var allowRemoteImages = false
    @State private var confirmDisconnect = false

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some View {
        TabView {
            accountTab.tabItem { Label(L10n.t("settings.tab.account"), systemImage: "person.crop.circle") }
            privacyTab.tabItem { Label(L10n.t("settings.tab.privacy"), systemImage: "hand.raised") }
            diagnosticsTab.tabItem { Label(L10n.t("settings.tab.diagnostics"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var model: MailoAppModel { root.active }

    private var accountTab: some View {
        Form {
            Section {
                LabeledContent("Email", value: accountEmail)
            }
            Section {
                Button(role: .destructive) {
                    confirmDisconnect = true
                } label: {
                    Text(L10n.t("settings.disconnect"))
                }
                .disabled(!isConnected)
            } footer: {
                Text(L10n.t("settings.disconnect.confirm"))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L10n.t("settings.disconnect"),
                            isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(L10n.t("settings.disconnect"), role: .destructive) {
                disconnect()
            }
        }
    }

    private var privacyTab: some View {
        Form {
            Section {
                Toggle(L10n.t("settings.remoteImages"), isOn: $allowRemoteImages)
            } footer: {
                Text(L10n.t("settings.remoteImages.hint"))
            }
        }
        .formStyle(.grouped)
    }

    private var diagnosticsTab: some View {
        Form {
            Section(L10n.t("settings.tab.diagnostics")) {
                LabeledContent(L10n.t("settings.diagnostics.schema"),
                               value: model.store.schemaDiagnostics())
                LabeledContent(L10n.t("settings.diagnostics.lastSync"),
                               value: model.lastSyncSummary.isEmpty ? "—" : model.lastSyncSummary)
                LabeledContent(L10n.t("settings.diagnostics.backfill"),
                               value: "\(model.backfilledCount)")
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
    }

    private var isConnected: Bool {
        if case .connected = model.phase { return true }
        return false
    }

    private var accountEmail: String {
        if case .connected(let email) = model.phase { return email }
        if case .demo = model.phase { return "demo@local" }
        return L10n.t("account.notConnected")
    }

    /// 断开连接（JOURNEY-016）：清凭证与账户记录，回账户页；Keychain 凭证随删。
    private func disconnect() {
        #if os(macOS) || os(iOS)
        model.disconnect(vault: KeychainVault())
        #else
        model.disconnect()
        #endif
        root.exitDemo()
    }
}
