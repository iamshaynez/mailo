import Testing

@testable import DesignKit

@MainActor
struct QuickReplyTests {
    @Test("JOURNEY-024 回复草稿按 stableId 隔离并恢复")
    func journey_024_drafts_are_isolated() {
        var store = QuickReplyStore()
        store.setText("For John", for: "x")
        store.setText("For Sarah", for: "y")
        #expect(store.text(for: "x") == "For John")
        #expect(store.text(for: "y") == "For Sarah")
        store.setText("   ", for: "x")
        #expect(!store.canSend(for: "x"))
        #expect(store.canSend(for: "y"))
    }

    @Test("JOURNEY-024 慢发送完成不清理另一封或新编辑的草稿")
    func journey_024_send_state_and_stale_completion() {
        var store = QuickReplyStore()
        store.setText("Original", for: "x")
        #expect(store.beginSend(for: "x") == "Original")
        #expect(!store.canSend(for: "x"))

        store.setText("Other message", for: "y")
        store.succeedSend(for: "x", sentText: "Original")
        #expect(store.text(for: "x") == "")
        #expect(store.text(for: "y") == "Other message")

        store.setText("First version", for: "x")
        _ = store.beginSend(for: "x")
        store.setText("Edited while sending", for: "x")
        store.succeedSend(for: "x", sentText: "First version")
        #expect(store.text(for: "x") == "Edited while sending")

        store.setText("Will fail", for: "y")
        _ = store.beginSend(for: "y")
        store.failSend(for: "y", message: "offline")
        #expect(store.text(for: "y") == "Will fail")
        #expect(store.state(for: "y") == .failed("offline"))
        #expect(store.canSend(for: "y"))
    }

    @Test("JOURNEY-024/JOURNEY-011 快速回复复用 Reply 元数据并拼接引用")
    func journey_024_quick_reply_payload() {
        let original = ComposeDraft(kind: .reply, to: "sender@x.co", subject: "Re: Hello",
                                    body: "\n\nOn sender@x.co wrote:\n> original")
        let payload = QuickReplyPayload.draft(userText: "  Sounds good.  ", replyingTo: original)
        #expect(payload.to == "sender@x.co")
        #expect(payload.subject == "Re: Hello")
        #expect(payload.body == "Sounds good.\n\nOn sender@x.co wrote:\n> original")
        #expect(payload.kind == .reply)
    }
}
