import CoreKit
import Foundation
import Network

// MARK: - 行读取器（MAIL-016，纯逻辑可测）

/// TLS 字节流 → 完整 IMAP 逻辑行（含 RFC3501 字面量整体）。
/// 生产与测试共用：生产由 NWConnection 分片喂入，测试直接喂任意切分。
public final class ImapLineReader: @unchecked Sendable {
    private var buffer: [UInt8] = []
    /// 有效区起点（PERF-007）：提取行只推进游标，feed 尾部定期压缩——
    /// 避免旧实现每行 `removeFirst` 的 O(缓冲区) 头部移位（大响应二次方退化）。
    private var head = 0
    /// 已确认不含 CRLF 起点的前缀边界（绝对坐标，PERF-007）：避免分片喂入时
    /// 对「未到齐的行尾」反复全量重扫（每 feed 一次 O(剩余缓冲) 的二次方退化）。
    private var scanFloor = 0
    /// 累计逐字节扫描量（PERF-007 门禁）：线性实现 ≈ 输入量的常数倍；
    /// 反复重扫/头部移位的退化实现随样本平方增长。
    public private(set) var scannedBytes = 0
    private static let compactThreshold = 1 << 16

    public init() {}

    /// 喂入新到的分片；返回本次凑齐的所有完整逻辑行（无则空数组）。
    public func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer += chunk
        var lines: [[UInt8]] = []
        while let line = tryExtractLine() {
            lines.append(line)
        }
        if head >= Self.compactThreshold {
            buffer.removeFirst(head)
            // 相对坐标平移（scanFloor 恒 ≤ head+consumed，平移后取 0 下界）
            scanFloor = max(0, scanFloor - head)
            head = 0
        }
        return lines
    }

    private func tryExtractLine() -> [UInt8]? {
        // 游标式提取：行(CRLF) [字面量 N 字节 + 行剩余(CRLF)]*
        // RFC3501：{N}\r\n 后紧跟 N 字节数据，其后直接是行剩余部分（无额外 CRLF）
        guard let firstCRLF = findCRLF(from: head) else { return nil }
        var line = Array(buffer[head..<firstCRLF])
        var consumed = (firstCRLF - head) + 2

        while let count = trailingLiteralCount(in: line) {
            guard buffer.count >= head + consumed + count else { return nil } // 数据未到齐，整体不消费
            line += [13, 10]
            line += Array(buffer[(head + consumed)..<(head + consumed + count)])
            consumed += count
            // 字面量数据直接接行剩余（无额外 CRLF，RFC3501）；剩余到下一 CRLF
            guard let c2 = findCRLF(from: head + consumed) else { return nil }
            line += Array(buffer[(head + consumed)..<c2])
            consumed = (c2 - head) + 2
        }
        head += consumed
        return line
    }

    private func findCRLF(from start: Int) -> Int? {
        // 起点单调（head 与 head+consumed 均只前进），[start, scanFloor) 已被
        // 此前调用确认无 CRLF 起点，直接跳过；成功时推进边界到命中点。
        // 失败时边界留在 count-1：末字节可能是未配对的 CR，跨界 CRLF 待下个分片判定。
        var i = max(start, scanFloor)
        let scanStart = i
        while i + 1 < buffer.count {
            if buffer[i] == 13, buffer[i + 1] == 10 {
                scanFloor = i
                scannedBytes += i - scanStart + 2
                return i
            }
            i += 1
        }
        scannedBytes += buffer.count - scanStart
        scanFloor = max(0, buffer.count - 1)
        return nil
    }

    /// 行尾是否为 `{N}` 或 `{N+}`（非同步字面量）。
    private func trailingLiteralCount(in line: [UInt8]) -> Int? {
        guard let brace = line.lastIndex(of: UInt8(ascii: "{")) else { return nil }
        var i = brace + 1
        var digits = ""
        while i < line.count, line[i] >= 48, line[i] <= 57 {
            digits.append(Character(UnicodeScalar(line[i])))
            i += 1
        }
        guard !digits.isEmpty else { return nil }
        // {N}：} 为行尾字符；{N+}：} 在倒数第二
        if i + 1 == line.count, line[i] == UInt8(ascii: "}") { return Int(digits) }
        if i + 2 == line.count, line[i] == UInt8(ascii: "}"), line[i + 1] == UInt8(ascii: "+") { return Int(digits) }
        return nil
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

    /// 读取一块原始字节（不切行）。IMAP 大响应（FETCH 流）必须走此路径：
    /// 行切分-重组会与字面量数据内部字节互相干扰，原始流直读无失真。
    func receiveRaw(timeout: TimeInterval = 30) throws -> [UInt8] {
        if !receiveBuffer.isEmpty {
            let out = receiveBuffer
            receiveBuffer = []
            return out
        }
        return try receiveChunk(timeout: timeout)
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
