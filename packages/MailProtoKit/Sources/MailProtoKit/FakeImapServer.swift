import Foundation

/// 进程内假 IMAP 服务器（基线 §8：测试基建的核心投资）。
/// 产出**真实形态的响应文本字节**，与生产 TCP 服务器同构——解析器、同步引擎
/// 都直接吃它的输出。可配置：能力集、UIDVALIDITY、消息库（含 GBK 主题等真实怪癖）。
public typealias Message = FakeImapServer.Message

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
    private var tagCounter = 0
    private let lock = NSLock()

    public init(capabilities: [String] = ["IMAP4rev1", "UIDPLUS", "CONDSTORE", "QRESYNC"],
                mailboxes: [String: Mailbox] = ["INBOX": Mailbox(uidValidity: 7)]) {
        self.capabilities = capabilities
        self.mailboxes = mailboxes
    }

    public func send(_ command: ImapCommand) throws -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        sentCommands.append(command)
        tagCounter += 1
        let tag = "A\(tagCounter)"
        var out = ""
        switch command {
        case .capability:
            out += "* CAPABILITY \(capabilities.joined(separator: " "))\r\n"
            out += "\(tag) OK CAPABILITY completed\r\n"

        case .login:
            out += "\(tag) OK LOGIN completed\r\n"

        case .select(let folder):
            guard let box = mailboxes[folder] else {
                out += "\(tag) NO SELECT no such mailbox\r\n"
                break
            }
            out += "* \(box.messages.count) EXISTS\r\n"
            out += "* OK [UIDVALIDITY \(box.uidValidity)] UIDs valid\r\n"
            out += "* OK [UIDNEXT \(box.messages.map(\.uid).max().map { $0 + 1 } ?? 1)] Predicted next UID\r\n"
            out += "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen)\r\n"
            out += "\(tag) OK [READ-WRITE] SELECT completed\r\n"

        case .fetchUid(let range, let items):
            guard let box = mailboxes["INBOX"] else {
                out += "\(tag) NO FETCH no mailbox selected\r\n"
                break
            }
            let wanted = uids(matching: range, in: box)
            var fetchBytes: [UInt8] = []
            for (seq, msg) in box.messages.enumerated() where wanted.contains(msg.uid) {
                fetchBytes += fetchLine(seq: seq + 1, message: msg, items: items)
            }
            fetchBytes += Array("\(tag) OK FETCH completed\r\n".utf8)
            return Array(out.utf8) + fetchBytes

        case .storeFlags(let uid, let flags):
            guard var box = mailboxes["INBOX"] else {
                out += "\(tag) NO STORE no mailbox\r\n"
                break
            }
            guard let index = box.messages.firstIndex(where: { $0.uid == uid }) else {
                out += "\(tag) NO STORE no such message\r\n"
                break
            }
            box.messages[index].flags.formUnion(flags)
            mailboxes["INBOX"] = box
            out += "\(tag) OK STORE completed\r\n"

        case .noop:
            out += "\(tag) OK NOOP completed\r\n"
        }
        return Array(out.utf8)
    }

    // MARK: - 响应构造（真实形态，供 ImapParser 消费）

    private func uids(matching range: String, in box: Mailbox) -> Set<Int> {
        let maxUid = box.messages.map(\.uid).max() ?? 0
        if range.hasSuffix(":*"), let low = Int(range.dropLast(2)) {
            return Set(box.messages.map(\.uid).filter { $0 >= low }) // "N:*" = N..maxUid
        }
        if range == "1:*" { return Set(box.messages.map(\.uid)) }
        // 形如 "2,5:9" 的 UID 集合
        var result = Set<Int>()
        for part in range.split(separator: ",") {
            let s = String(part)
            if s.contains(":") {
                let bounds = s.split(separator: ":").compactMap { Int($0) }
                if bounds.count == 2 {
                    result.formUnion(min(bounds[0], bounds[1])...max(bounds[0], bounds[1]))
                }
            } else if let u = Int(s) {
                result.insert(u)
            }
        }
        return result
    }

    private func fetchLine(seq: Int, message: Message, items: String) -> [UInt8] {
        let upper = items.uppercased()
        var out: [UInt8] = Array("* \(seq) FETCH (".utf8)
        var parts: [String] = []
        if upper.contains("UID") { parts.append("UID \(message.uid)") }
        if upper.contains("FLAGS") {
            parts.append("FLAGS (\(message.flags.sorted().joined(separator: " ")))")
        }
        if upper.contains("INTERNALDATE") {
            parts.append("INTERNALDATE \"\(message.internalDate)\"")
        }
        if upper.contains("ENVELOPE") {
            parts.append("ENVELOPE \(envelope(of: message))")
        }
        out += Array(parts.joined(separator: " ").utf8)
        if upper.contains("BODY[]") || upper.contains("BODY.PEEK[]") {
            if !parts.isEmpty { out += [UInt8(ascii: " ")] }
            out += Array("BODY[] {\(message.raw.count)}\r\n".utf8) // 字面量头
            out += message.raw
        }
        out += Array(")\r\n".utf8)
        return out
    }

    /// ENVELOPE 10 项（RFC3501 顺序）：date subject from sender reply-to to cc bcc in-reply-to message-id
    private func envelope(of message: Message) -> String {
        let headers = Self.headers(of: message.raw)
        let date = headers["date"].map { Self.quote($0) } ?? "NIL"
        let subject = headers["subject"].map { Self.quote($0) } ?? "NIL"
        let from: String
        if let addr = headers["from"] {
            let pieces = addr.split(separator: "@")
            if pieces.count == 2 {
                from = "((NIL NIL \(Self.quote(String(pieces[0]))) \(Self.quote(String(pieces[1])))))"
            } else {
                from = "((NIL NIL \(Self.quote(addr)) NIL))"
            }
        } else {
            from = "NIL"
        }
        let mid = headers["message-id"].map { Self.quote($0) } ?? "NIL"
        return "(\(date) \(subject) \(from) NIL NIL NIL NIL NIL NIL \(mid))"
    }

    private static func quote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// 头解析：小写键，忽略 continuation 简化（MIME 层另有完整实现，见 CoreKit.Mime）。
    static func headers(of raw: [UInt8]) -> [String: String] {
        var map: [String: String] = [:]
        var currentKey: String?
        for lineRaw in String(decoding: raw, as: UTF8.self).components(separatedBy: "\r\n") {
            if lineRaw.isEmpty { break } // 头区结束
            if let key = currentKey, lineRaw.hasPrefix(" ") || lineRaw.hasPrefix("\t") {
                map[key, default: ""] += " " + lineRaw.trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let colon = lineRaw.firstIndex(of: ":") else { continue }
            let key = lineRaw[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = lineRaw[lineRaw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            map[key] = value
            currentKey = key
        }
        return map
    }
}
