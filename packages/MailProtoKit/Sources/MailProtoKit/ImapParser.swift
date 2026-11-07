import Foundation

/// IMAP 响应 token：字符串 / 字面量字节 / 括号列表（递归）。
public enum ImapAtom: Equatable, Sendable {
    case string(String)
    case literal([UInt8])
    case list([ImapAtom])
}

/// 解析后的一行（tagged/untagged/continuation 的差别在 atoms[0] 可辨）。
public struct ParsedLine: Equatable, Sendable {
    public var atoms: [ImapAtom]
    public init(atoms: [ImapAtom]) { self.atoms = atoms }
}

/// IMAP 响应字节流解析器：行 + 括号列表 + RFC3501 字面量 `{N}` 跨行续传（MAIL-004）。
public enum ImapParser {
    public enum ParseError: Error, Equatable {
        case truncated
        case badLiteralCount(String)
    }

    /// 解析完整响应字节（多行）。输入不完整时抛 .truncated（调用方攒够再调）。
    public static func parse(_ bytes: [UInt8]) throws -> [ParsedLine] {
        var i = 0
        let n = bytes.count
        var lines: [ParsedLine] = []
        var current: [ImapAtom] = []
        var stack: [[ImapAtom]] = []

        func finishLine() {
            // 未闭合的括号挂在栈上（不合式输入），此处只按行收束
            while let open = stack.popLast() {
                current = open + current
            }
            lines.append(ParsedLine(atoms: current))
            current = []
        }

        while i < n {
            let c = bytes[i]
            switch c {
            case UInt8(ascii: " "):
                i += 1

            case UInt8(ascii: "("):
                stack.append(current)
                current = []
                i += 1

            case UInt8(ascii: ")"):
                let inner = current
                guard let open = stack.popLast() else {
                    current.append(.string(")"))
                    i += 1
                    continue
                }
                current = open
                current.append(.list(inner))
                i += 1

            case UInt8(ascii: "\""):
                var j = i + 1
                var s = ""
                while j < n, bytes[j] != UInt8(ascii: "\"") {
                    if bytes[j] == UInt8(ascii: "\\"), j + 1 < n { j += 1 }
                    s.append(Character(UnicodeScalar(bytes[j])))
                    j += 1
                }
                if j >= n { throw ParseError.truncated }
                current.append(.string(s))
                i = j + 1

            case UInt8(ascii: "{"):
                // {N}\r\n 后立即跟 N 字节字面量（RFC3501）
                var j = i + 1
                var countStr = ""
                while j < n, bytes[j] != UInt8(ascii: "}") {
                    countStr.append(Character(UnicodeScalar(bytes[j])))
                    j += 1
                }
                guard let count = Int(countStr.trimmingCharacters(in: .whitespaces)) else {
                    throw ParseError.badLiteralCount(countStr)
                }
                // 消费 "}\r\n"（RFC3501 字面量头）
                guard j + 3 <= n,
                      bytes[j] == UInt8(ascii: "}"),
                      bytes[j + 1] == UInt8(ascii: "\r"),
                      bytes[j + 2] == UInt8(ascii: "\n") else { throw ParseError.truncated }
                let dataStart = j + 3
                guard dataStart + count <= n else { throw ParseError.truncated }
                current.append(.literal(Array(bytes[dataStart..<(dataStart + count)])))
                i = dataStart + count

            case UInt8(ascii: "\r") where i + 1 < n && bytes[i + 1] == UInt8(ascii: "\n"):
                finishLine()
                i += 2

            default:
                var j = i
                while j < n,
                      bytes[j] != UInt8(ascii: " "),
                      bytes[j] != UInt8(ascii: "("),
                      bytes[j] != UInt8(ascii: ")"),
                      bytes[j] != UInt8(ascii: "\r") {
                    j += 1
                }
                let token = String(decoding: bytes[i..<j], as: UTF8.self)
                current.append(.string(token))
                i = j
            }
        }
        if !current.isEmpty { finishLine() }
        return lines
    }
}

/// FETCH 响应的语义提取（MAIL-003）。
public struct FetchData: Equatable, Sendable {
    public var uid: Int
    public var flags: [String]
    public var internalDate: String
    public var subject: String?
    public var fromAddress: String?
    public var messageId: String?
    public var rawHeader: [UInt8]?

    public init(uid: Int, flags: [String], internalDate: String,
                subject: String? = nil, fromAddress: String? = nil,
                messageId: String? = nil, rawHeader: [UInt8]? = nil) {
        self.uid = uid
        self.flags = flags
        self.internalDate = internalDate
        self.subject = subject
        self.fromAddress = fromAddress
        self.messageId = messageId
        self.rawHeader = rawHeader
    }

    /// 从 `* n FETCH (...)` 的 atoms 提取。ENVELOPE 顺序（RFC3501）：
    /// date subject (from...) (sender...) (reply-to...) to cc bcc in-reply-to message-id
    public static func extract(from line: ParsedLine, header: [UInt8]? = nil) -> FetchData? {
        // 形如 [*, seq, FETCH, list]；tagged 行或其他不匹配的返回 nil
        guard line.atoms.count >= 4,
              case .string(let seqEnd) = line.atoms[0], seqEnd == "*",
              case .string(let verb) = line.atoms[2], verb.uppercased() == "FETCH",
              case .list(let items) = line.atoms[3] else { return nil }

        var uid = 0, flags: [String] = [], date = ""
        var subject: String?, from: String?, mid: String?

        var k = 0
        while k + 1 < items.count + 1, k < items.count {
            guard case .string(let key) = items[k] else { k += 1; continue }
            let value = k + 1 < items.count ? items[k + 1] : nil
            switch key.uppercased() {
            case "UID":
                if case .string(let v) = value, let u = Int(v) { uid = u }
            case "FLAGS":
                if case .list(let f) = value {
                    flags = f.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                }
            case "INTERNALDATE":
                if case .string(let v) = value { date = v }
            case "ENVELOPE":
                if case .list(let env) = value {
                    // env[1] subject, env[2] from, env[9] message-id
                    if env.count > 1 {
                        switch env[1] {
                        case .string(let s): subject = EncodedWord.decode(s)
                        case .list(let words):
                            subject = words.compactMap { if case .string(let s) = $0 { return EncodedWord.decode(s) } else { return nil } }.joined(separator: " ")
                        default: break
                        }
                    }
                    if env.count > 2, case .list(let fromGroup) = env[2],
                       let first = fromGroup.first, case .list(let addr) = first, addr.count >= 4,
                       case .string(let mailbox) = addr[2], case .string(let host) = addr[3] {
                        from = "\(mailbox)@\(host)"
                    }
                    if env.count > 9, case .string(let m) = env[9] { mid = m }
                }
            default: break
            }
            k += 2
        }
        return FetchData(uid: uid, flags: flags, internalDate: date,
                         subject: subject, fromAddress: from, messageId: mid, rawHeader: header)
    }
}
