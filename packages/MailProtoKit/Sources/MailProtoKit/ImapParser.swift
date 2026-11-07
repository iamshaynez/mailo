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
    /// 解析完整响应字节（多行）。未终止的输入抛错（调用方攒够再调）。
    public static func parse(_ bytes: [UInt8]) throws -> [ParsedLine] {
        // PLACEHOLDER (red phase)
        return []
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
        // PLACEHOLDER (red phase)
        return nil
    }
}
