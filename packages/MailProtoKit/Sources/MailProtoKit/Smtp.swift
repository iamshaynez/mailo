import CoreKit
import Foundation

/// SMTP 命令（MAIL-013 会话子集）。
public enum SmtpCommand: Equatable, Sendable {
    case ehlo(domain: String)
    case authLogin(user: String, passRef: String) // passRef 由调用方从 Keychain 解出后注入传输层，此处只留痕迹
    case authXoauth2(user: String, accessToken: String) // MAIL-024：OAuth 单命令认证
    case mailFrom(String)
    case rcptTo(String)
    case data
    case dotData([UInt8])
    case quit

    public var wire: String? {
        switch self {
        case .ehlo(let d): return "EHLO \(d)"
        case .authLogin: return "AUTH LOGIN"
        case .authXoauth2(let user, let token): return "AUTH XOAUTH2 \(Sasl.xoauth2(user: user, accessToken: token))"
        case .mailFrom(let a): return "MAIL FROM:<\(a)>"
        case .rcptTo(let a): return "RCPT TO:<\(a)>"
        case .data: return "DATA"
        case .quit: return "QUIT"
        case .dotData: return nil // 数据块不走单行 wire
        }
    }
}

/// SMTP 应答：三位码 + 多行文本。
public struct SmtpReply: Equatable, Sendable {
    public var code: Int
    public var lines: [String]

    public init(code: Int, lines: [String] = []) {
        self.code = code
        self.lines = lines
    }

    public var isPositive: Bool { (200...399).contains(code) }
}

/// SMTP 传输端口（生产：Network.framework TCP + TLS；测试：FakeSmtpServer）。
public protocol SmtpTransport: Sendable {
    func execute(_ command: SmtpCommand) throws -> SmtpReply
    var executedCommands: [SmtpCommand] { get }
}

public enum SmtpError: Error, Equatable {
    case rejected(stage: String, code: Int)
}

/// SMTP 客户端：一次完整发信会话（MAIL-013/014）。
public struct SmtpClient: Sendable {
    public var domain: String // EHLO 标识（本机域名，常用 "mailo.local"）

    public init(domain: String = "mailo.local") {
        self.domain = domain
    }

    /// 发送一封纯文本邮件。返回构造出的完整 DATA 块字节（供测试与 "Sent" 归档复用）。
    @discardableResult
    public func send(from: String, to: String, subject: String, body: String,
                     user: String, passRef: String, transport: any SmtpTransport) throws -> [UInt8] {
        return try send(from: from, to: to, subject: subject, body: body,
                        auth: .login(user: user, password: passRef), transport: transport)
    }

    /// 认证参数化发信（MAIL-024：xoauth2 走单命令；login 走交互轮询由传输层处理）。
    public func send(from: String, to: String, subject: String, body: String,
                     auth: Auth, transport: any SmtpTransport) throws -> [UInt8] {
        let authCommand: SmtpCommand
        switch auth {
        case .login(let user, let password): authCommand = .authLogin(user: user, passRef: password)
        case .xoauth2(let user, let token): authCommand = .authXoauth2(user: user, accessToken: token)
        }
        let steps: [(String, SmtpCommand, Int)] = [
            ("EHLO", .ehlo(domain: domain), 250),
            ("AUTH", authCommand, 235),
            ("MAIL FROM", .mailFrom(from), 250),
            ("RCPT TO", .rcptTo(to), 250),
            ("DATA", .data, 354),
        ]
        for (stage, command, expected) in steps {
            let reply = try transport.execute(command)
            guard reply.code == expected else {
                throw SmtpError.rejected(stage: stage, code: reply.code)
            }
        }

        let payload = Self.dataBlock(from: from, to: to, subject: subject, body: body)
        let accepted = try transport.execute(.dotData(payload))
        guard accepted.code == 250 else {
            throw SmtpError.rejected(stage: "DOT", code: accepted.code)
        }
        _ = try transport.execute(.quit)
        return payload
    }

    /// DATA 块构造（MAIL-014）：头齐全 + 点填充 + `CRLF.CRLF` 终止。
    public static func dataBlock(from: String, to: String, subject: String, body: String) -> [UInt8] {
        let messageId = "<mailo-\(UUID().uuidString)@local>"
        let date = ISO8601DateFormatter().string(from: Date())
        var out = "Message-ID: \(messageId)\r\n"
        out += "From: \(from)\r\n"
        out += "To: \(to)\r\n"
        out += "Subject: \(subject)\r\n"
        out += "Date: \(date)\r\n"
        out += "MIME-Version: 1.0\r\n"
        out += "Content-Type: text/plain; charset=utf-8\r\n"
        out += "Content-Transfer-Encoding: 8bit\r\n"
        out += "\r\n"
        // 点填充：正文行以 '.' 开头时前置一个 '.'
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
            out += trimmed.hasPrefix(".") ? "." + trimmed : trimmed
            out += "\r\n"
        }
        out += ".\r\n"
        return Array(out.utf8)
    }
}

/// 进程内假 SMTP 服务器：记录会话，可注入失败。
public final class FakeSmtpServer: SmtpTransport, @unchecked Sendable {
    public private(set) var executedCommands: [SmtpCommand] = []
    public var failAt: [String: Int] = [:] // stage 简名 → 错误码，如 ["RCPT TO": 550]
    public var lastDataBlock: [UInt8] = []
    private let lock = NSLock()

    public init() {}

    public func execute(_ command: SmtpCommand) throws -> SmtpReply {
        lock.lock(); defer { lock.unlock() }
        executedCommands.append(command)
        if case .dotData(let bytes) = command { lastDataBlock = bytes }
        let expected: [String: Int] = ["EHLO": 250, "AUTH": 235, "MAIL FROM": 250,
                                       "RCPT TO": 250, "DATA": 354, "DOT": 250, "QUIT": 221]
        let stage = stageName(command)
        if let failCode = failAt[stage] {
            return SmtpReply(code: failCode, lines: ["injected failure"])
        }
        return SmtpReply(code: expected[stage] ?? 250, lines: ["ok"])
    }

    private func stageName(_ c: SmtpCommand) -> String {
        switch c {
        case .ehlo: return "EHLO"
        case .authLogin: return "AUTH"
        case .mailFrom: return "MAIL FROM"
        case .rcptTo: return "RCPT TO"
        case .data: return "DATA"
        case .dotData: return "DOT"
        case .quit: return "QUIT"
        }
    }
}
