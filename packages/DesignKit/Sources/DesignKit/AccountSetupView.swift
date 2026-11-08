import AuthKit
import CoreKit
import MailProtoKit
import SwiftUI

/// 账户添加向导（真实 Outlook 设备码授权，JOURNEY-002 的 UI 面）。
/// 状态机：填表 → 显示 user_code → 连接中 → 完成/失败；附"先看看 Demo"（独立内存库，JOURNEY-010）。
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
        VStack(spacing: 24) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.brandBlue)
            Text("Welcome to Mailo")
                .font(.system(size: 28, weight: .heavy))
            Text("No cloud. Zero data leaves your device. Connect your mailbox:")
                .foregroundColor(DesignTokens.inkMuted)

            switch model.phase {
            case .connecting(let prompt):
                promptView(prompt)

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                connectForm

            default:
                connectForm
            }

            Button("Try the demo (no account needed)") {
                root.enterDemo()
            }
            .font(.system(size: 12))
            .foregroundColor(DesignTokens.inkMuted)
        }
        .padding(48)
        .frame(maxWidth: 520)
    }

    private var connectForm: some View {
        VStack(spacing: 12) {
            TextField("Email (you@outlook.com)", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            TextField("Entra Client ID", text: $clientId)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            Button {
                busy = true
                Task {
                    defer { busy = false }
                    // 传 KeychainVault：refresh token 落 Keychain，下次启动免授权（JOURNEY-005 曾因漏传而失效）
                    try? await model.connectOutlook(email: email, clientId: clientId, vault: KeychainVault())
                }
            } label: {
                if busy { ProgressView().frame(maxWidth: .infinity) }
                else { Text("Connect Outlook").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.brandBlue)
            .disabled(email.isEmpty || clientId.isEmpty || busy)
        }
    }

    @ViewBuilder
    private func promptView(_ prompt: DeviceCodeClient.Prompt?) -> some View {
        if let prompt {
            VStack(spacing: 12) {
                Text("Finish sign-in in your browser").font(.headline)
                Text("Open \(prompt.verificationURI)")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.inkMuted)
                Text(prompt.userCode)
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(DesignTokens.brandBlue)
                if let url = URL(string: prompt.verificationURI) {
                    Link("Open sign-in page", destination: url)
                        .buttonStyle(.bordered)
                }
                ProgressView().padding(.top, 8)
            }
        } else {
            ProgressView("Requesting a device code from Microsoft…")
        }
    }
}

