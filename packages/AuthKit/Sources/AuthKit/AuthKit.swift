import CoreKit
import Foundation

/// 服务商授权配置常量（OAUTH-001）。
/// ⚠ Gmail 只接受全量 scope（基线 §4.1 决策点：M1 末用真实 consent 屏复核）。
public enum OAuthProviderConfig {
    public static let gmailImapHost = "imap.gmail.com"
    public static let gmailSmtpHost = "smtp.gmail.com"
    public static let gmailScopes = ["https://mail.google.com/"]

    public static let outlookImapHost = "outlook.office365.com"
    public static let outlookSmtpHost = "smtp.office365.com"
    public static let outlookAuthority = "https://login.microsoftonline.com/common"
    public static let outlookScopes = [
        "https://outlook.office365.com/IMAP.AccessAsUser.All",
        "https://outlook.office365.com/SMTP.Send",
    ]

    /// OAuth 回跳 scheme：`msauth.<bundle id>://auth` 的 scheme 部分。
    public static func redirectScheme(bundleId: String) -> String {
        "msauth.\(bundleId)"
    }
}

/// OAuth client 注册信息（占位注入：client id 注册后由配置下发/编译注入，永不入库）。
public struct OAuthClientInfo: Equatable, Sendable, Codable {
    public var provider: Provider
    public var clientId: String
    public var bundleId: String

    public enum Provider: String, Equatable, Sendable, Codable {
        case gmail
        case outlook
    }

    public init(provider: Provider, clientId: String, bundleId: String) {
        self.provider = provider
        self.clientId = clientId
        self.bundleId = bundleId
    }
}

/// 凭证保管端口（OAUTH-002）。生产实现走 Keychain(Security.framework)；
/// 授权码账户与 OAuth token 都经此口，明文永不落盘文件。
public protocol CredentialVault: Sendable {
    func save(_ secret: String, for ref: String) throws
    func load(_ ref: String) throws -> String?
    func delete(_ ref: String) throws
    /// 全部引用键（不含明文；用于账户列表与孤儿清理）。
    func allRefs() throws -> [String]
}

/// 进程内实现（测试与预览）。
public final class InMemoryVault: CredentialVault, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ secret: String, for ref: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[ref] = secret
    }

    public func load(_ ref: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[ref]
    }

    public func delete(_ ref: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[ref] = nil
    }

    public func allRefs() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(store.keys)
    }
}

/// OAuth token 会话（OAUTH-003）。
public struct OAuthSession: Equatable, Sendable, Codable {
    public var accessToken: String
    public var refreshToken: String?
    /// epoch 秒
    public var expiresAt: TimeInterval

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: TimeInterval) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// 过期前 60 秒即视为需刷新（提前量避免竞态）。
    public func needsRefresh(now: TimeInterval) -> Bool {
        now >= expiresAt - 60
    }
}
