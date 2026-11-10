import AuthKit
import Foundation
import SwiftUI

/// JOURNEY-024：每封邮件独立的快速回复发送状态。
enum QuickReplySendState: Equatable {
    case idle, sending, sent, failed(String)
}

/// JOURNEY-024：按 stableId 隔离快速回复草稿与发送生命周期。
struct QuickReplyStore {
    private var drafts: [String: String] = [:]
    private var states: [String: QuickReplySendState] = [:]

    func text(for stableId: String) -> String { drafts[stableId] ?? "" }
    func state(for stableId: String) -> QuickReplySendState { states[stableId] ?? .idle }

    /// JOURNEY-024：仅非空且未在发送中的草稿可以发送。
    func canSend(for stableId: String) -> Bool {
        let hasText = !text(for: stableId).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText && state(for: stableId) != .sending
    }

    mutating func setText(_ text: String, for stableId: String) { drafts[stableId] = text }

    /// JOURNEY-024：规范化待发正文并进入 sending；空正文或重复发送返回 nil。
    mutating func beginSend(for stableId: String) -> String? {
        let trimmed = text(for: stableId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state(for: stableId) != .sending else { return nil }
        drafts[stableId] = trimmed
        states[stableId] = .sending
        return trimmed
    }

    /// JOURNEY-024：仅清理仍与已发送文本相同的草稿，保留发送期间的新编辑。
    mutating func succeedSend(for stableId: String, sentText: String) {
        if drafts[stableId] == sentText {
            drafts[stableId] = ""
            states[stableId] = .sent
        } else {
            states[stableId] = .idle
        }
    }

    /// JOURNEY-024：失败保留当前草稿，并记录可重试的错误状态。
    mutating func failSend(for stableId: String, message: String) {
        states[stableId] = .failed(message)
    }
}

/// JOURNEY-024/JOURNEY-011：快速回复复用原回复草稿的元数据与引用。
enum QuickReplyPayload {
    static func draft(userText: String, replyingTo original: ComposeDraft) -> ComposeDraft {
        var draft = original
        draft.body = userText.trimmingCharacters(in: .whitespacesAndNewlines) + original.body
        return draft
    }
}

/// 快速回复实际总高度观测，供 HTML 正文视口扣除（JOURNEY-014/024）。
struct ReplyHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = DesignTokens.quickReplyHeight + 16
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 阅读区内嵌快速回复（JOURNEY-024）：真实草稿、SMTP 发送与完整撰写出口。
struct QuickReplyView: View {
    @ObservedObject var model: MailoAppModel
    let stableId: String
    let recipientName: String
    @Binding var store: QuickReplyStore
    let replyFocusRequest: Int
    let onExpand: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: Binding<String> {
        Binding(get: { store.text(for: stableId) },
                set: { store.setText($0, for: stableId) })
    }

    private var state: QuickReplySendState { store.state(for: stableId) }
    private var isDemo: Bool { model.phase == .demo }
    private var expanded: Bool {
        focused || state == .sending || state.isFailure
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            inputCard
            sendButton
        }
        .padding(.leading, ReaderSurfaceSpec.leadingPadding)
        .padding(.trailing, ReaderSurfaceSpec.trailingPadding)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ReplyHeightPreference.self, value: proxy.size.height)
            }
        }
        .onChange(of: replyFocusRequest) { _ in focused = true }
        .onChange(of: stableId) { _ in focused = false }
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: expanded)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: focused)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: state)
    }

    private var inputCard: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                if case .failed(let message) = state {
                    Text(message)
                        .font(DesignTokens.Typo.micro)
                        .foregroundColor(DesignTokens.statusDanger)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7)
                        .padding(.top, 1)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: text)
                        .font(DesignTokens.Typo.body)
                        .foregroundColor(DesignTokens.inkBody)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .focused($focused)
                        .padding(.horizontal, 2)
                        .accessibilityLabel(L10n.t("quickReply.placeholder", recipientName))
                    if text.wrappedValue.isEmpty {
                        Text(L10n.t("quickReply.placeholder", recipientName))
                            .font(DesignTokens.Typo.meta)
                            .foregroundColor(DesignTokens.inkMuted)
                            .padding(.horizontal, 7)
                            .padding(.top, 7)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
            .help(L10n.t("quickReply.expand"))
            .accessibilityLabel(L10n.t("quickReply.expand"))
            .padding(.leading, 4)
            .padding(.bottom, 2)

            if state == .sent {
                Label(L10n.t("quickReply.sent"), systemImage: "checkmark.circle.fill")
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.accentDeep)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: expanded ? DesignTokens.quickReplyExpandedHeight : DesignTokens.quickReplyHeight)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch).fill(DesignTokens.surfaceSearch))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                .strokeBorder(focused ? DesignTokens.accent : DesignTokens.borderDefault,
                              lineWidth: focused ? 1.5 : 1)
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: 6) {
                if state == .sending {
                    ProgressView().controlSize(.small)
                } else {
                    Text(L10n.t("compose.send"))
                    Image(systemName: "arrow.right")
                }
            }
            .font(DesignTokens.Typo.caption)
            .foregroundColor(DesignTokens.onAccent)
            .padding(.horizontal, 14)
            .frame(height: DesignTokens.replySendHeight)
            .background(Capsule().fill(DesignTokens.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(store.canSend(for: stableId) ? 1 : 0.45)
        .disabled(!store.canSend(for: stableId))
        .help(isDemo ? L10n.t("quickReply.demo") : L10n.t("quickReply.send"))
        .accessibilityLabel(L10n.t("quickReply.send"))
    }

    private func send() {
        var next = store
        guard let userText = next.beginSend(for: stableId) else { return }
        store = next
        if isDemo {
            next.failSend(for: stableId, message: L10n.t("quickReply.demo"))
            store = next
            return
        }
        guard let original = model.composeDraft(for: stableId, kind: .reply) else {
            next.failSend(for: stableId, message: L10n.t("reader.missing"))
            store = next
            return
        }
        let payload = QuickReplyPayload.draft(userText: userText, replyingTo: original)
        let target = stableId
        Task { @MainActor in
            do {
                try await model.composeAndSend(to: payload.to, subject: payload.subject, body: payload.body,
                                               vault: KeychainVault())
                var completed = store
                completed.succeedSend(for: target, sentText: userText)
                store = completed
            } catch {
                var failed = store
                let detail = error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
                failed.failSend(for: target, message: L10n.t("compose.sendFailed", detail))
                store = failed
            }
        }
    }
}

private extension QuickReplySendState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

