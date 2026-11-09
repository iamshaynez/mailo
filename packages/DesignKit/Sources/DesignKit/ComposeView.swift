import AuthKit
import CoreKit
import SwiftUI

/// Slate Concept 撰写页（JOURNEY-006/011）：Reply/Forward 预填 → SMTP 发送。
/// ⌘↩ 发送；所有字段与按钮使用双主题 token。
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
                    .font(DesignTokens.Typo.title)
                    .foregroundColor(DesignTokens.inkPrimary)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                .accessibilityLabel(L10n.t("compose.title"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            VStack(spacing: 10) {
                field(L10n.t("compose.to"), text: $to)
                field(L10n.t("compose.subject"), text: $subject)
            }
            .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $bodyText)
                    .font(DesignTokens.Typo.body)
                    .foregroundColor(DesignTokens.inkBody)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if bodyText.isEmpty {
                    Text(L10n.t("compose.bodyPlaceholder"))
                        .font(DesignTokens.Typo.body)
                        .foregroundColor(DesignTokens.inkMuted)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: DesignTokens.radiusCard).fill(DesignTokens.surfaceCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                .strokeBorder(DesignTokens.borderDefault))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let errorText {
                Text(errorText)
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.statusDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            Button(action: send) {
                HStack {
                    if sending {
                        ProgressView()
                            .tint(DesignTokens.onAccent)
                    }
                    Text(L10n.t("compose.send"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MailoButtonStyle(variant: .primary))
            .modifier(DesignTokens.primaryShadow())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(to.isEmpty || subject.isEmpty || sending)
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(DesignTokens.surfaceReader)
        .mailoAppearance()
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(DesignTokens.Typo.body)
            .foregroundColor(DesignTokens.inkPrimary)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch).fill(DesignTokens.surfaceCard))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                .strokeBorder(DesignTokens.borderDefault))
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
