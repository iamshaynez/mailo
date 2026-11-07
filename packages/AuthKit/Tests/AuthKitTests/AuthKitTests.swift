import Testing
import CoreKit
@testable import AuthKit

// MARK: - 用例库：docs/specs/OAUTH-usecases.md（OAUTH-001 ~ 003）

struct AuthKitTests {

    @Test("OAUTH-001 服务商授权配置常量")
    func oauth_001_provider_constants() {
        #expect(OAuthProviderConfig.gmailScopes == ["https://mail.google.com/"])
        #expect(OAuthProviderConfig.gmailImapHost == "imap.gmail.com")
        #expect(OAuthProviderConfig.outlookScopes.contains("https://outlook.office365.com/IMAP.AccessAsUser.All"))
        #expect(OAuthProviderConfig.outlookScopes.contains("https://outlook.office365.com/SMTP.Send"))
        #expect(OAuthProviderConfig.outlookAuthority == "https://login.microsoftonline.com/common")
        #expect(OAuthProviderConfig.redirectScheme(bundleId: "com.xiaowenz.mailo") == "msauth.com.xiaowenz.mailo")
    }

    @Test("OAUTH-002 凭证保管（端口语义）")
    func oauth_002_credential_vault_semantics() throws {
        let vault = InMemoryVault()
        try vault.save("token-abc", for: "mailo.acct.1234")
        #expect(try vault.load("mailo.acct.1234") == "token-abc")

        try vault.delete("mailo.acct.1234")
        #expect(try vault.load("mailo.acct.1234") == nil)

        try vault.save("t1", for: "k1")
        try vault.save("t2", for: "k2")
        let refs = try vault.allRefs()
        #expect(Set(refs) == Set(["k1", "k2"])) // 仅引用键，无明文
    }

    @Test("OAUTH-003 token 会话刷新判定")
    func oauth_003_session_refresh_window() {
        let session = OAuthSession(accessToken: "a", refreshToken: "r", expiresAt: 1_000)
        #expect(session.needsRefresh(now: 1_000 - 61) == false) // 提前量外
        #expect(session.needsRefresh(now: 1_000 - 59) == true)  // 60s 窗口内
        #expect(session.needsRefresh(now: 2_000) == true)       // 早已过期
    }
}
