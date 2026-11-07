import CryptoKit
import Foundation

/// 邮箱账户配置（授权码体系：QQ/163/自建 IMAP，基线 D10）。
/// 授权码永不入本结构——只存 Keychain 引用（MAIL-015 的机密隔离）。
public struct AccountConfig: Equatable, Sendable, Codable {
    public var displayName: String
    public var imapHost: String
    public var imapPort: Int
    public var smtpHost: String
    public var smtpPort: Int
    public var username: String
    /// Keychain 条目引用（如 "mailo.acct.<fingerprint>"）；不存任何明文凭证
    public var secretRef: String

    public init(displayName: String, imapHost: String, imapPort: Int = 993,
                smtpHost: String, smtpPort: Int = 465,
                username: String, secretRef: String) {
        self.displayName = displayName
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.username = username
        self.secretRef = secretRef
    }

    /// 账号指纹：稳定主键的组成部（基线 §3）。host+user 规范化后哈希，大小写/空白无关。
    public var fingerprint: String {
        let canonical = "\(imapHost.normalized)|\(smtpHost.normalized)|\(username.normalized)"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
