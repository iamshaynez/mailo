import AuthKit
import CoreKit
import MailProtoKit
import SwiftUI

/// Slate Concept 账户向导（JOURNEY-002/010）：填表 → 设备码 → 连接；Demo 独立内存库。
public struct AccountSetupView: View {
    @ObservedObject var root: MailoRootModel
    @ObservedObject var model: MailoAppModel
    @State private var email = ""
    @State private var clientId = ""
    @State private var busy = false

    public init(root: MailoRootModel) {
        self.root = root
        self.model = root.live
    }

    public var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("m")
                    .font(DesignTokens.Typo.iconLarge.weight(.bold))
                    .foregroundColor(DesignTokens.brandBlue)
                Circle().fill(DesignTokens.brandBlue).frame(width: 6, height: 6)
            }
            Text(L10n.t("setup.welcome"))
                .font(DesignTokens.Typo.title)
                .foregroundColor(DesignTokens.inkPrimary)
            Text(L10n.t("setup.subtitle"))
                .font(DesignTokens.Typo.body)
                .foregroundColor(DesignTokens.inkMuted)
                .multilineTextAlignment(.center)

            switch model.phase {
            case .connecting(let prompt):
                promptView(prompt)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(DesignTokens.statusDanger)
                    .font(DesignTokens.Typo.meta)
                    .multilineTextAlignment(.center)
                connectForm
            default:
                connectForm
            }

            Button(L10n.t("setup.tryDemo")) {
                root.enterDemo()
            }
            .buttonStyle(MailoButtonStyle(variant: .ghost))
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusWindow).fill(DesignTokens.surfaceCard))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusWindow)
            .strokeBorder(DesignTokens.borderHairline))
        .shadow(color: DesignTokens.shadowColor.opacity(0.12), radius: 18, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surfaceReader)
    }

    private var connectForm: some View {
        VStack(spacing: 12) {
            setupField(L10n.t("setup.emailPlaceholder"), text: $email)
            setupField(L10n.t("setup.clientId"), text: $clientId)
            Button {
                busy = true
                Task {
                    defer { busy = false }
                    try? await model.connectOutlook(email: email, clientId: clientId, vault: KeychainVault())
                }
            } label: {
                HStack {
                    if busy { ProgressView().tint(DesignTokens.onAccent) }
                    Text(L10n.t("setup.connect"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MailoButtonStyle(variant: .primary))
            .modifier(DesignTokens.primaryShadow())
            .disabled(email.isEmpty || clientId.isEmpty || busy)
        }
    }

    private func setupField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(DesignTokens.Typo.body)
            .foregroundColor(DesignTokens.inkPrimary)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch).fill(DesignTokens.surfaceControl))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                .strokeBorder(DesignTokens.borderDefault))
    }

    @ViewBuilder
    private func promptView(_ prompt: DeviceCodeClient.Prompt?) -> some View {
        if let prompt {
            VStack(spacing: 12) {
                Text(L10n.t("setup.devicecode.title"))
                    .font(DesignTokens.Typo.sub)
                    .foregroundColor(DesignTokens.inkPrimary)
                Text(L10n.t("setup.devicecode.open", prompt.verificationURI))
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkMuted)
                Text(prompt.userCode)
                    .font(DesignTokens.Typo.deviceCode)
                    .tracking(4)
                    .foregroundStyle(DesignTokens.brandBlue)
                if let url = URL(string: prompt.verificationURI) {
                    Link(L10n.t("setup.devicecode.link"), destination: url)
                        .buttonStyle(MailoButtonStyle(variant: .secondary))
                }
                ProgressView()
                    .tint(DesignTokens.brandBlue)
                    .padding(.top, 8)
            }
        } else {
            ProgressView(L10n.t("setup.devicecode.requesting"))
                .tint(DesignTokens.brandBlue)
        }
    }
}
