import CoreKit
import Foundation
import Network

// MARK: - 行读取器（MAIL-016，纯逻辑可测）

/// TLS 字节流 → 完整 IMAP 逻辑行（含 RFC3501 字面量整体）。
/// 生产与测试共用：生产由 NWConnection 分片喂入，测试直接喂任意切分。
public final class ImapLineReader: @unchecked Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// 喂入新到的分片；返回本次凑齐的所有完整逻辑行（无则空数组）。
    public func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer += chunk
        var lines: [[UInt8]] = []
        while let line = tryExtractLine() {
            lines.append(line)
        }
        return lines
    }

    private func tryExtractLine() -> [UInt8]? {
        // 找 CRLF
        guard let crlf = findCRLF() else { return nil }
        var line = Array(buffer[0..<crlf])
        buffer.removeFirst(crlf + 2)

        // 行尾 {N} → 字面量：需要 N 字节 + CRLF，之后行继续（逻辑行未完）
        while let openBrace = line.lastIndex(of: UInt8(ascii: "{")),
              line.last == UInt8(ascii: "}") || literalTail(line, brace: openBrace),
              let count = literalCount(in: line, brace: openBrace) {
            let needed = count + 2 // 字面量 + 其 CRLF
            guard buffer.count >= needed else {
                // 数据不足：把行放回等待更多分片
                buffer = line + [13, 10] + buffer
                return nil
            }
            line += [13, 10]
            line += Array(buffer[0..<count])
            line += Array(buffer[(count)..<(count + 2)])
            buffer.removeFirst(needed)
        }
        return line
    }

    private func findCRLF() -> Int? {
        for i in 0..<(buffer.count >= 1 ? buffer.count - 1 : 0) {
            if buffer[i] == 13, buffer[i + 1] == 10 { return i }
        }
        // 边界：单个 \r 在末尾也算不完整，继续等
        return nil
    }

    private func literalTail(_ line: [UInt8], brace: Int) -> Bool {
        // 形如 ...{123}（之后无内容）才算行尾字面量头
        return line.indices.last == brace + countDigitsSuffix(line, from: brace) + 1
    }

    private func countDigitsSuffix(_ line: [UInt8], from: Int) -> Int {
        var n = 0
        var i = from + 1
        while i < line.count, line[i] >= 48, line[i] <= 57 { n += 1; i += 1 }
        return n
    }

    private func literalCount(in line: [UInt8], brace: Int) -> Int? {
        var digits = ""
        var i = brace + 1
        while i < line.count, line[i] >= 48, line[i] <= 57 {
            digits.append(Character(UnicodeScalar(line[i])))
            i += 1
        }
        guard i < line.count, line[i] == UInt8(ascii: "}") else { return nil }
        // 大括号后有 + 号（非同步字面量）按普通处理
        if i + 1 < line.count, line[i + 1] == UInt8(ascii: "+") { i += 1 }
        guard i == line.count - 1 else { return nil } // 必须行尾
        return Int(digits)
    }
}

// MARK: - XOAUTH2 SASL（MAIL-017）

public enum Sasl {
    /// Gmail/Outlook IMAP & SMTP 共用的 XOAUTH2 初始响应。
    public static func xoauth2(user: String, accessToken: String) -> String {
        let raw = "user=\(user)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(raw.utf8).base64EncodedString()
    }

    /// 服务器拒绝（+ 错误基串）后的空响应（终止协商）。
    public static let emptyResponse = ""
}

// MARK: - SMTP 多行应答解析（MAIL-018）

public enum SmtpReplyParser {
    /// `250-` 续行 / `250 `(或 `250-` 后无更多) 终行 → 归并单条应答。
    public static func parse(_ lines: [String]) -> SmtpReply? {
        var code = 0
        var texts: [String] = []
        for (i, line) in lines.enumerated() {
            guard line.count >= 4,
                  let c = Int(line.prefix(3)),
                  line[line.index(line.startIndex, offsetBy: 3)] == "-" || line[line.index(line.startIndex, offsetBy: 3)] == " " else {
                return nil
            }
            let text = String(line.dropFirst(4))
            if i == 0 { code = c }
            guard c == code else { return nil }
            texts.append(text)
            if line[line.index(line.startIndex, offsetBy: 3)] == " " {
                return SmtpReply(code: code, lines: texts) // 终行：忽略其后
            }
        }
        return nil // 未出现终行
    }
}

// MARK: - TLS 连接基础（MAIL-019）

/// NWConnection(TLS) 的最小同步封装：连接/发送/收行/关闭。
/// 生产调用侧应在后台队列驱动；域层端口保持同步形态。
final class TlsConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "mailo.tls")
    private var receiveBuffer: [UInt8] = []

    init(host: String, port: UInt16) {
        let hostEndpoint = NWEndpoint.Host(host)
        let tlsOptions = NWProtocolTLS.Options()
        let params = NWParameters(tls: tlsOptions)
        connection = NWConnection(host: hostEndpoint, port: NWEndpoint.Port(rawValue: port)!, using: params)
    }

    func connect(timeout: TimeInterval = 10) throws {
        let sem = DispatchSemaphore(value: 0)
        var connectError: Error?
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: sem.signal()
            case .failed(let e): connectError = e; sem.signal()
            case .cancelled: sem.signal()
            default: break
            }
        }
        connection.start(queue: queue)
        guard sem.wait(timeout: .now() + timeout) == .success else {
            throw TransportError.timeout("connect")
        }
        if let e = connectError { throw e }
    }

    func send(_ bytes: [UInt8]) throws {
        let sem = DispatchSemaphore(value: 0)
        var sendError: Error?
        connection.send(content: Data(bytes), completion: .contentProcessed { error in
            sendError = error
            sem.signal()
        })
        guard sem.wait(timeout: .now() + 15) == .success else { throw TransportError.timeout("send") }
        if let e = sendError { throw e }
    }

    /// 读取一行（CRLF 终结，返回不含 CRLF）。
    func receiveLine(timeout: TimeInterval = 15) throws -> [UInt8] {
        while true {
            if let idx = receiveBuffer.firstIndex(of: 13), idx + 1 < receiveBuffer.count, receiveBuffer[idx + 1] == 10 {
                let line = Array(receiveBuffer[0..<idx])
                receiveBuffer.removeFirst(idx + 2)
                return line
            }
            let chunk = try receiveChunk(timeout: timeout)
            receiveBuffer += chunk
        }
    }

    /// 读取 N 字节（字面量数据）。
    func receiveBytes(_ count: Int, timeout: TimeInterval = 30) throws -> [UInt8] {
        while receiveBuffer.count < count {
            receiveBuffer += try receiveChunk(timeout: timeout)
        }
        let out = Array(receiveBuffer[0..<count])
        receiveBuffer.removeFirst(count)
        return out
    }

    private func receiveChunk(timeout: TimeInterval) throws -> [UInt8] {
        let sem = DispatchSemaphore(value: 0)
        var received: Data?
        var error: Error?
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, e in
            error = e
            if let c = content { received = c }
            if isComplete && content == nil { error = TransportError.closed }
            sem.signal()
        }
        guard sem.wait(timeout: .now() + timeout) == .success else { throw TransportError.timeout("receive") }
        if let e = error { throw e }
        return received.map { [UInt8]($0) } ?? []
    }

    func close() {
        connection.cancel()
    }
}

public enum TransportError: Error, Equatable {
    case timeout(String)
    case closed
    case rejected(String)
}
