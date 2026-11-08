import AuthKit
import CoreKit
import SwiftUI

/// 撰写邮件（JOURNEY-006/011）：Reply/Forward 预填（to/subject/引用正文）→ SMTP XOAUTH2 发送。
/// ⌘↩ 发送；关闭有内容时留驻（v1 不做草稿持久化，关闭即弃）。
public struct ComposeView: View {
    @ObservedObject var model: MailoAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var sending = false
    @State private var errorText: String?

    public init(model: MailoAppModel, draft: ComposeDraft = ComposeDraft()) {
        self.model = model
        _to = State(initialValue: draft.to)
        _subject = State(initialValue: draft.subject)
        _bodyText = State(initialValue: draft.body)
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
                        Text("Write something…").foregroundColor(DesignTokens.inkFaint).padding(16)
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11.5))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            HStack {
                Button(action: send) {
                    if sending { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Send").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.brandBlue)
                .keyboardShortcut(.return, modifiers: .command) // ⌘↩ 发送（Mac 惯例）
                .disabled(to.isEmpty || subject.isEmpty || sending)
                .padding(16)
            }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            defer { sending = false }
            do {
                try await model.composeAndSend(to: to, subject: subject, body: bodyText,
                                               vault: KeychainVault())
                dismiss()
            } catch {
                errorText = "Send failed: \(error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription)"
            }
        }
    }
}
