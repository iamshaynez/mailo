import CoreKit
import Foundation

/// 生产 IMAP 传输：TLS 直连（993），LOGIN 或 XOAUTH2 认证（MAIL-019）。
/// 真实联调需用户环境（邮箱账号/授权码）；CI 验证编译、构造与端口符合性。
public final class TcpImapTransport: ImapTransport, @unchecked Sendable {
    private var connection: TlsConnection?
    public let host: String
    public let port: UInt16
    public let connectTimeout: TimeInterval
    private var tagCounter = 0
    private var nextTag: String { tagCounter += 1; return "M\(tagCounter)" }
    /// 命令互斥（MAIL-025）：轮询/回填/阅读拉取并发共用本连接，
    /// 命令-响应往返必须串行化，否则响应按 tag 交叉污染导致超时。
    private let commandLock = NSLock()

    public init(host: String, port: UInt16 = 993, connectTimeout: TimeInterval = 10) {
        self.host = host
        self.port = port
        self.connectTimeout = connectTimeout
    }

    public enum AuthMethod: Equatable, Sendable {
        case login(user: String, password: String)
        case xoauth2(user: String, accessToken: String)
    }

    /// 连接并认证：读问候 → LOGIN 或 AUTHENTICATE XOAUTH2。
    public func connect(method: AuthMethod) throws {
        let conn = TlsConnection(host: host, port: port)
        try conn.connect(timeout: connectTimeout)
        connection = conn
        _ = try conn.receiveLine() // * OK greeting

        switch method {
        case .login(let user, let password):
            let tag = nextTag
            try conn.send(Array("\(tag) LOGIN \"\(user)\" \"\(password)\"\r\n".utf8))
            _ = try readUntilTagged(tag)
        case .xoauth2(let user, let token):
            let tag = nextTag
            let sasl = Sasl.xoauth2(user: user, accessToken: token)
            try conn.send(Array("\(tag) AUTHENTICATE XOAUTH2 \(sasl)\r\n".utf8))
            // 服务器或直接 tagged OK，或 "+ base64错误" 需空响应终止
            let first = try conn.receiveLine()
            if first.first == UInt8(ascii: "+") {
                try conn.send(Array("\(Sasl.emptyResponse)\r\n".utf8))
                _ = try readUntilTagged(tag)
            } else if String(decoding: first, as: UTF8.self).hasPrefix(tag) {
                // 直接完成
            } else {
                _ = try readUntilTagged(tag)
            }
        }
    }

    /// 端口实现：发送命令，收集到 tagged 终结行为止的完整响应字节（含字面量整体）。
    /// 全程持命令锁（MAIL-025）。
    public func send(_ command: ImapCommand) throws -> [UInt8] {
        commandLock.lock(); defer { commandLock.unlock() }
        guard let conn = connection else { throw TransportError.closed }
        let tag = nextTag
        try conn.send(Array("\(tag) \(command.wire)\r\n".utf8))
        return try readUntilTagged(tag, conn: conn)
    }

    private func readUntilTagged(_ tag: String, conn: TlsConnection? = nil) throws -> [UInt8] {
        guard let conn = conn ?? connection else { throw TransportError.closed }
        var out: [UInt8] = []
        let reader = ImapLineReader()
        while true {
            let chunk = try conn.receiveRaw()
            for logical in reader.feed(chunk) {
                out += logical
                if String(decoding: logical, as: UTF8.self).hasPrefix(tag) {
                    return out
                }
            }
        }
    }
}

/// 生产 SMTP 传输：TLS 直连（465），EHLO/AUTH LOGIN 流程（MAIL-019）。
public final class TcpSmtpTransport: SmtpTransport, @unchecked Sendable {
    private var connection: TlsConnection?
    public let host: String
    public let port: UInt16
    public let connectTimeout: TimeInterval
    public private(set) var executedCommands: [SmtpCommand] = []
    private let lock = NSLock()

    public init(host: String, port: UInt16 = 465, connectTimeout: TimeInterval = 10) {
        self.host = host
        self.port = port
        self.connectTimeout = connectTimeout
    }

    public func connect(timeout: TimeInterval? = nil) throws {
        let conn = TlsConnection(host: host, port: port)
        try conn.connect(timeout: timeout ?? connectTimeout)
        connection = conn
        _ = try readReply() // 220 greeting
    }

    /// 执行一条命令并读取应答（多行归并）。
    public func execute(_ command: SmtpCommand) throws -> SmtpReply {
        lock.lock(); defer { lock.unlock() }
        executedCommands.append(command)
        guard let conn = connection else { throw TransportError.closed }
        switch command {
        case .dotData(let bytes):
            try conn.send(bytes)
        default:
            try conn.send(Array(((command.wire ?? "") + "\r\n").utf8))
        }
        if case .authLogin(let user, let passRef) = command {
            // AUTH LOGIN：334 → base64(user) → 334 → base64(passRef)
            _ = try readReply() // 334 user prompt
            try conn.send(Array((Data(user.utf8).base64EncodedString() + "\r\n").utf8))
            _ = try readReply() // 334 pass prompt
            try conn.send(Array((Data(passRef.utf8).base64EncodedString() + "\r\n").utf8))
        }
        return try readReply()
    }

    private func readReply() throws -> SmtpReply {
        guard let conn = connection else { throw TransportError.closed }
        var lines: [String] = []
        while true {
            let line = String(decoding: try conn.receiveLine(), as: UTF8.self)
            lines.append(line)
            // 终行：`NNN `（第 4 字符为空格）或长度仅 3
            if line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == " " { break }
            if line.count == 3 { break }
        }
        guard let reply = SmtpReplyParser.parse(lines) else {
            throw TransportError.rejected("unparseable reply: \(lines)")
        }
        return reply
    }
}
