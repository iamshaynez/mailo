import Testing
import Foundation
@testable import AuthKit

// MARK: - 用例库：docs/specs/OAUTH-usecases.md（OAUTH-004）

/// CI macos runner 的登录 keychain 已解锁，可真实走 SecItem 路径。
/// 每次用独立 service 前缀隔离，收尾清理。
struct KeychainVaultTests {

    @Test("OAUTH-004 Keychain 生产实现（真实读写）")
    func oauth_004_keychain_vault_real() throws {
        let service = "com.xiaowenz.mailo.test-\(UUID().uuidString.prefix(8))"
        defer { try? KeychainVault(service: service).delete("k1"); try? KeychainVault(service: service).delete("k2") }
        let vault = KeychainVault(service: service)

        // 存/取往返
        try vault.save("secret-α-123", for: "k1")
        #expect(try vault.load("k1") == "secret-α-123")

        // 更新（同 ref 覆盖）
        try vault.save("secret-β-456", for: "k1")
        #expect(try vault.load("k1") == "secret-β-456")

        // 删除后取不到；重复删除幂等
        try vault.delete("k1")
        #expect(try vault.load("k1") == nil)
        try vault.delete("k1") // 不抛

        // 枚举只含引用键
        try vault.save("t1", for: "k1")
        try vault.save("t2", for: "k2")
        #expect(Set(try vault.allRefs()) == Set(["k1", "k2"]))
        // 隔离性：不含其他 service 的条目
        #expect(try vault.load("nonexistent") == nil)
    }
}
