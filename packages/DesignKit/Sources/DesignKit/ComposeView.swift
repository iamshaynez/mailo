import AuthKit
import CoreKit
import SwiftUI

/// 撰写邮件（JOURNEY-006 的 UI 面）：To/Subject/Body → SMTP XOAUTH2 发送。
public struct ComposeView: View {
    @ObservedObject var model: MailoAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var sending = false
    @State private var errorText: String?

    public init(model: MailoAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Message")
                    .font(.system(size: 16, weight: .heavy))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignTokens.inkFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Form {
                TextField("To", text: $to)
                TextField("Subject", text: $subject)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 120)

            TextEditor(text: $bodyText)
                .font(.system(size: 14))
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("正文…").foregroundColor(DesignTokens.inkFaint).padding(16)
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11.5))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            HStack {
                Button {
                    sending = true
                    errorText = nil
                    Task {
                        defer { sending = false }
                        do {
                            try await model.composeAndSend(to: to, subject: subject, body: bodyText,
                                                           vault: KeychainVault())
                            dismiss()
                        } catch {
                            errorText = "发送失败：\(error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription)"
                        }
                    }
                } label: {
                    if sending { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Send").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.brandBlue)
                .disabled(to.isEmpty || subject.isEmpty || sending)
                .padding(16)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }
}
