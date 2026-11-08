import Testing
import Foundation
@testable import CoreKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-023）

struct EmailAddressTests {

    @Test("MAIL-023 发件人地址解析（显示名剥离）")
    func mail_023_from_display_name_parse() {
        // 显示名 + 尖括号（真实 Outlook/Gmail 最常见形态）
        let a = EmailAddress.parse("\"Sarah Chen\" <sarah@wave.co>")
        #expect(a?.address == "sarah@wave.co")
        #expect(a?.domain == "wave.co")
        #expect(a?.display == "Sarah Chen")

        // 无引号显示名
        #expect(EmailAddress.parse("Sarah Chen <sarah@Wave.CO>")?.address == "sarah@wave.co")

        // 纯地址
        let c = EmailAddress.parse("alerts@netflix.com")
        #expect(c?.address == "alerts@netflix.com")
        #expect(c?.display == nil)

        // 尾注释
        #expect(EmailAddress.parse("boss@corp.com (Boss)")?.address == "boss@corp.com")

        // 坏输入
        #expect(EmailAddress.parse(nil) == nil)
        #expect(EmailAddress.parse("") == nil)
        #expect(EmailAddress.parse("not-an-address") == nil)
        #expect(EmailAddress.parse("broken <x") == nil)
    }
}
