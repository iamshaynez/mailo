import CoreKit
import Foundation
import MailProtoKit

/// 已连接账户的本地档案（JOURNEY-005）：email/clientId/账户形态存 JSON 文件；
/// 凭证本身在 CredentialVault（Keychain），文件里只有 secretRef 引用。
public struct AccountRecord: Codable, Equatable, Sendable {
    public var email: String
    public var clientId: String
    public var accountKind: String // DeviceCodeFlow.MicrosoftAccount.rawValue
    public var secretRef: String

    public init(email: String, clientId: String,
                accountKind: DeviceCodeFlow.MicrosoftAccount = .personal,
                secretRef: String) {
        self.email = email
        self.clientId = clientId
        self.accountKind = accountKind.rawValue
        self.secretRef = secretRef
    }
}

public final class AccountStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("accounts.json")
    }

    public func save(_ record: AccountRecord) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode([record])
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadPrimary() -> AccountRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([AccountRecord].self, from: data) else { return nil }
        return list.first
    }

    public func wipe() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
