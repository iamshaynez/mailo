import Foundation

/// 进程内假 IMAP 服务器（基线 §8：测试基建的核心投资）。
/// 产出**真实形态的响应文本字节**，与生产 TCP 服务器同构——解析器、同步引擎
/// 都直接吃它的输出。可配置：能力集、UIDVALIDITY、消息库（含 GBK 主题等真实怪癖）。
public final class FakeImapServer: ImapTransport, @unchecked Sendable {
    public struct Message: Sendable {
        public var uid: Int
        public var flags: Set<String>
        public var internalDate: String
        /// 完整原始邮件字节（头 + 体），服务器按 FETCH items 切片返回
        public var raw: [UInt8]

        public init(uid: Int, flags: Set<String> = [], internalDate: String = "07-Nov-2026 10:00:00 +0000", raw: [UInt8]) {
            self.uid = uid
            self.flags = flags
            self.internalDate = internalDate
            self.raw = raw
        }
    }

    public struct Mailbox: Sendable {
        public var uidValidity: Int
        public var messages: [Message]

        public init(uidValidity: Int, messages: [Message] = []) {
            self.uidValidity = uidValidity
            self.messages = messages
        }
    }

    public var capabilities: [String]
    public var mailboxes: [String: Mailbox]
    public private(set) var sentCommands: [ImapCommand] = []
    private let lock = NSLock()

    public init(capabilities: [String] = ["IMAP4rev1", "UIDPLUS", "CONDSTORE", "QRESYNC"],
                mailboxes: [String: Mailbox] = ["INBOX": Mailbox(uidValidity: 7)]) {
        self.capabilities = capabilities
        self.mailboxes = mailboxes
    }

    public func send(_ command: ImapCommand) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        sentCommands.append(command)
        // PLACEHOLDER (red phase)
        return Array("* BAD placeholder\r\n".utf8)
    }
}
