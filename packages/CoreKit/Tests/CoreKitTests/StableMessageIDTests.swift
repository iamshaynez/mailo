import Testing
@testable import CoreKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md

struct StableMessageIDTests {

    @Test("MAIL-001 稳定主键规范化且与 UID 无关")
    func mail_001_stable_id_normalizes_and_ignores_uid() {
        // 带 URI 括号/大小写/内空白的 Message-ID 与干净形态是同一封邮件
        let a = StableMessageID(messageId: "<ABC-123@smtp.CORP.com>", accountFingerprint: "acct-9")
        let b = StableMessageID(messageId: "abc-123@smtp.corp.com", accountFingerprint: "acct-9")
        #expect(a == b)

        // 账号指纹不同 → 不同主键（多账号同邮件互不串扰）
        let c = StableMessageID(messageId: "<ABC-123@smtp.CORP.com>", accountFingerprint: "acct-8")
        #expect(a != c)

        // 构造签名不含任何 UID/文件夹参数：UIDVALIDITY 重置不影响主键
        // （编译层面即保证——本测试同时作为 API 形状回归）
    }

    @Test("MAIL-002 Message-ID 缺失时 fallback 确定性")
    func mail_002_fallback_id_is_deterministic() {
        let f1 = StableMessageID.FallbackInputs(from: "a@b.c", date: "2026-11-07T10:00:00Z", subject: "Hi")
        let f2 = StableMessageID.FallbackInputs(from: "a@b.c", date: "2026-11-07T10:00:00Z", subject: "Hi")
        let g = StableMessageID.FallbackInputs(from: "a@b.c", date: "2026-11-07T10:00:00Z", subject: "Hello")

        let x1 = StableMessageID(messageId: nil, accountFingerprint: "acct-9", fallback: f1)
        let x2 = StableMessageID(messageId: nil, accountFingerprint: "acct-9", fallback: f2)
        let y = StableMessageID(messageId: nil, accountFingerprint: "acct-9", fallback: g)

        #expect(x1 == x2)   // 相同输入 → 相同主键
        #expect(x1 != y)    // 任一输入不同 → 不同主键
    }
}
