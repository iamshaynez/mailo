import AuthKit
import CoreKit
import SwiftUI

/// 撰写邮件（JOURNEY-006/011）：Reply/Forward 预填（to/subject/引用正文）→ SMTP XOAUTH2 发送。
/// ⌘↩ 发送；关闭有内容时留驻（v1 不做草稿持久化，关闭即弃）。
public struct ComposeView: View {
    @ObservedObject var model: MailoAppModel
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var sending = false
    @State private var errorText: String?

    public init(model: MailoAppModel, draft: ComposeDraft = ComposeDraft(), onDismiss: (() -> Void)? = nil) {
        self.model = model
        self.onDismiss = onDismiss
        _to = State(initialValue: draft.to)
        _subject = State(initialValue: draft.subject)
        _bodyText = State(initialValue: draft.body)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("compose.title"))
                    .font(DesignTokens.Typo.sub)
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignTokens.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("compose.title"))
            }
            .padding(16)

            Form {
                TextField(L10n.t("compose.to"), text: $to)
                TextField(L10n.t("compose.subject"), text: $subject)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 120)

            TextEditor(text: $bodyText)
                .font(DesignTokens.Typo.body)
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text(L10n.t("compose.bodyPlaceholder")).foregroundColor(DesignTokens.inkFaint).padding(16)
                    }
                }

            if let errorText {
                Text(errorText)
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            HStack {
                Button(action: send) {
                    if sending { ProgressView().frame(maxWidth: .infinity) }
                    else { Text(L10n.t("compose.send")).frame(maxWidth: .infinity) }
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

    private func close() {
        onDismiss?()
        dismiss()
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            defer { sending = false }
            do {
                try await model.composeAndSend(to: to, subject: subject, body: bodyText,
                                               vault: KeychainVault())
                close()
            } catch {
                errorText = L10n.t("compose.sendFailed", error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription)
            }
        }
    }
}
