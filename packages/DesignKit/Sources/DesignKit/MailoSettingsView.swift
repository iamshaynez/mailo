import AuthKit
import CoreKit
import SwiftUI

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-016 Settings 场景）

/// 设置（JOURNEY-016 v2）：Appearance / 账户 / 隐私 / 诊断。
/// macOS 由 Settings 场景承载（⌘,），iOS 由账户菜单 sheet 承载。
public struct MailoSettingsView: View {
    @ObservedObject var root: MailoRootModel
    @AppStorage("allowRemoteImages") private var allowRemoteImages = false
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system.rawValue
    @State private var confirmDisconnect = false

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some View {
        TabView {
            appearanceTab.tabItem { Label(L10n.t("settings.appearance"), systemImage: "circle.lefthalf.filled") }
            accountTab.tabItem { Label(L10n.t("settings.tab.account"), systemImage: "person.crop.circle") }
            privacyTab.tabItem { Label(L10n.t("settings.tab.privacy"), systemImage: "hand.raised") }
            diagnosticsTab.tabItem { Label(L10n.t("settings.tab.diagnostics"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(minWidth: 500, minHeight: 340)
        .background(DesignTokens.surfaceReader)
        .tint(DesignTokens.brandBlue)
        .mailoAppearance()
    }

    private var model: MailoAppModel { root.active }

    private var appearanceTab: some View {
        Form {
            Section {
                Picker(L10n.t("settings.appearance"), selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(L10n.t("settings.appearance.\(preference.rawValue)"))
                            .tag(preference.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityLabel(L10n.t("settings.appearance"))
            }
        }
        .formStyle(.grouped)
    }

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
