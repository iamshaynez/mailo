import Testing
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-022）

struct SelectStateTests {

    @Test("MAIL-022 SELECT 状态解析")
    func mail_022_select_state_parse() {
        // 真实 Outlook 响应形态（用户 2026-11-07 实测样本）
        let wire = """
        * 5100 EXISTS\r
        * 5100 RECENT\r
        * FLAGS (\\Seen \\Answered)\r
        * OK [PERMANENTFLAGS (\\Seen)] Permanent flags\r
        * OK [UNSEEN 4757] Is the first unseen message\r
        * OK [UIDVALIDITY 14] UIDVALIDITY value\r
        * OK [UIDNEXT 51518] The next unique identifier value\r
        M3 OK [READ-WRITE] SELECT completed.\r
        """
        let info = SelectState.parse(Array(wire.utf8))
        #expect(info.exists == 5100)
        #expect(info.uidNext == 51518)
        #expect(info.recentRange(count: 3) == "51515:*")

        // 退化为 1
        #expect(SelectState.Info(exists: 2, uidNext: 3).recentRange(count: 10) == "1:*")
    }
}
