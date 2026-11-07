import CoreKit
import MailProtoKit
import SwiftUI

/// 账户添加向导（真实 Outlook 设备码授权，JOURNEY-002 的 UI 面）。
/// 状态机：填表 → 显示 user_code → 连接中 → 完成/失败；附"先看看 Demo"。
public struct AccountSetupView: View {
    @ObservedObject var model: MailoAppModel
    @State private var email = ""
    @State private var clientId = ""
    @State private var busy = false

    public init(model: MailoAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.brandBlue)
            Text("欢迎使用 Mailo")
                .font(.system(size: 28, weight: .heavy))
            Text("无云 · 零数据出设备。先连接你的邮箱：")
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

            Button("先看看 Demo（无需账户）") {
                model.switchToDemo()
            }
            .font(.system(size: 12))
            .foregroundColor(DesignTokens.inkMuted)
        }
        .padding(48)
        .frame(maxWidth: 520)
    }

    private var connectForm: some View {
        VStack(spacing: 12) {
            TextField("邮箱（you@outlook.com）", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Entra Client ID", text: $clientId)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                busy = true
                Task {
                    defer { busy = false }
                    try? await model.connectOutlook(email: email, clientId: clientId)
                }
            } label: {
                if busy { ProgressView().frame(maxWidth: .infinity) }
                else { Text("连接 Outlook").frame(maxWidth: .infinity) }
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
                Text("在浏览器完成授权").font(.headline)
                Text("打开 \(prompt.verificationURI)")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.inkMuted)
                Text(prompt.userCode)
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(DesignTokens.brandBlue)
                if let url = URL(string: prompt.verificationURI) {
                    Link("打开授权页面", destination: url)
                        .buttonStyle(.bordered)
                }
                ProgressView().padding(.top, 8)
            }
        } else {
            ProgressView("正在向 Microsoft 请求设备码 …")
        }
    }
}

