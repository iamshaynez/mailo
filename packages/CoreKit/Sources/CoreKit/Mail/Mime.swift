import Foundation

/// MIME 叶子部分（传输解码后的字节 + 头）。
public struct MimePart: Equatable, Sendable {
    public var headers: [String: String]
    public var body: [UInt8]
    public var contentType: String
    public var filename: String?
    public var charset: String?

    public init(headers: [String: String] = [:], body: [UInt8],
                contentType: String, filename: String? = nil, charset: String? = nil) {
        self.headers = headers
        self.body = body
        self.contentType = contentType
        self.filename = filename
        self.charset = charset
    }
}

/// 邮件结构摘要（MAIL-011）：分类与展示所需的最小完备视图。
public struct ParsedEmail: Equatable, Sendable {
    public var headers: [String: String]
    public var messageId: String?
    public var subject: String?
    public var from: String?
    public var date: String?
    public var textBody: String?
    public var htmlBody: String?
    public var attachments: [MimePart]

    public init(headers: [String: String] = [:], messageId: String? = nil, subject: String? = nil,
                from: String? = nil, date: String? = nil, textBody: String? = nil,
                htmlBody: String? = nil, attachments: [MimePart] = []) {
        self.headers = headers
        self.messageId = messageId
        self.subject = subject
        self.from = from
        self.date = date
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
    }
}

/// MIME 解析器：头折叠、multipart 递归、传输编码、charset 解码（MAIL-008 ~ 012）。
public enum MimeParser {
    public static func parse(_ raw: [UInt8]) -> ParsedEmail {
        let (headerBytes, bodyBytes) = splitHeaderBody(raw)
        let headers = parseHeaders(String(decoding: headerBytes, as: UTF8.self))
        var email = ParsedEmail(headers: headers)
        email.messageId = headers["message-id"]
        email.subject = headers["subject"].map { EncodedWord.decode($0) }
        email.from = headers["from"]
        email.date = headers["date"]

        let (type, params) = parseContentType(headers["content-type"])
        var parts: [MimePart] = []
        collectParts(body: bodyBytes, type: type, params: params, headers: headers, into: &parts)

        for part in parts {
            switch part.contentType {
            case "text/plain" where email.textBody == nil:
                email.textBody = decodeText(part)
            case "text/html" where email.htmlBody == nil:
                email.htmlBody = decodeText(part)
            default:
                if isAttachment(part) { email.attachments.append(part) }
            }
        }
        return email
    }

    // MARK: - 结构

    static func splitHeaderBody(_ raw: [UInt8]) -> ([UInt8], [UInt8]) {
        let n = raw.count
        var i = 0
        while i + 3 < n {
            if raw[i] == 13, raw[i + 1] == 10, raw[i + 2] == 13, raw[i + 3] == 10 {
                return (Array(raw[0..<i]), Array(raw[(i + 4)...]))
            }
            if raw[i] == 10, raw[i + 1] == 10 { // 宽容 \n\n
                return (Array(raw[0..<i]), Array(raw[(i + 2)...]))
            }
            i += 1
        }
        return (raw, [])
    }

    /// 头解析：键小写、折叠续行以单空格并入（MAIL-008）。
    static func parseHeaders(_ block: String) -> [String: String] {
        var map: [String: String] = [:]
        var lastKey: String?
        let lines = block.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        for line in lines {
            if line.isEmpty { continue }
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let key = lastKey {
                    map[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            map[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            lastKey = key
        }
        return map
    }

    static func parseContentType(_ value: String?) -> (type: String, params: [String: String]) {
        guard let value, !value.isEmpty else { return ("text/plain", [:]) }
        let segments = value.split(separator: ";")
        let type = segments[0].trimmingCharacters(in: .whitespaces).lowercased()
        var params: [String: String] = [:]
        for seg in segments.dropFirst() {
            let kv = seg.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
            var v = kv[1].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 {
                v = String(v.dropFirst().dropLast())
            }
            params[k] = v
        }
        return (type, params)
    }

    static func collectParts(body: [UInt8], type: String, params: [String: String],
                             headers: [String: String], into out: inout [MimePart]) {
        if type.hasPrefix("multipart/"), let boundary = params["boundary"] {
            for segment in splitMultipart(body, boundary: boundary) {
                let (segHeader, segBody) = splitHeaderBody(segment)
                let segHeaders = parseHeaders(String(decoding: segHeader, as: UTF8.self))
                let (segType, segParams) = parseContentType(segHeaders["content-type"])
                collectParts(body: segBody, type: segType, params: segParams,
                             headers: segHeaders, into: &out)
            }
            return
        }
        let cte = headers["content-transfer-encoding"]?.lowercased() ?? ""
        let decoded = decodeTransfer(body, cte: cte)
        out.append(MimePart(
            headers: headers,
            body: decoded,
            contentType: type,
            filename: filename(of: headers, params: params),
            charset: params["charset"]?.lowercased()
        ))
    }

    static func splitMultipart(_ body: [UInt8], boundary: String) -> [[UInt8]] {
        let delimiter = "--\(boundary)"
        var segments: [[UInt8]] = []
        var current: [UInt8] = []
        var collecting = false
        let lines = splitLines(body)
        for line in lines {
            let s = String(decoding: line.bytes, as: UTF8.self)
            if s == delimiter {
                if collecting { segments.append(current) }
                current = []
                collecting = true
            } else if s == delimiter + "--" {
                if collecting { segments.append(current) }
                return segments
            } else if collecting {
                if !current.isEmpty { current += [13, 10] } // 恢复行间 CRLF（分隔符前的 CRLF 属分隔符）
                current += line.bytes
            }
        }
        return segments
    }

    /// 按行切（保留无终结符的末行），返回 (bytes, hadCRLF)。
    static func splitLines(_ bytes: [UInt8]) -> [(bytes: [UInt8], hadCRLF: Bool)] {
        var lines: [(bytes: [UInt8], hadCRLF: Bool)] = []
        var current: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 13, i + 1 < bytes.count, bytes[i + 1] == 10 {
                lines.append((current, true))
                current = []
                i += 2
            } else if bytes[i] == 10 {
                lines.append((current, true))
                current = []
                i += 1
            } else {
                current.append(bytes[i])
                i += 1
            }
        }
        if !current.isEmpty { lines.append((current, false)) }
        return lines
    }

    // MARK: - 编码

    static func decodeTransfer(_ bytes: [UInt8], cte: String) -> [UInt8] {
        switch cte {
        case "base64":
            let compact = bytes.filter { $0 != 13 && $0 != 10 && $0 != 32 && $0 != 9 }
            return Data(base64Encoded: Data(compact)).map { [UInt8]($0) } ?? bytes
        case "quoted-printable":
            return decodeQuotedPrintable(bytes)
        default: // 7bit / 8bit / binary / 空
            return bytes
        }
    }

    static func decodeQuotedPrintable(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == UInt8(ascii: "=") {
                if i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) {
                    let hex = String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self)
                    out.append(UInt8(hex, radix: 16) ?? UInt8(ascii: "="))
                    i += 3
                } else {
                    // 软换行：= 后的行终结符删除
                    i += 1
                    if i < bytes.count, bytes[i] == 13 {
                        i += 1
                        if i < bytes.count, bytes[i] == 10 { i += 1 }
                    } else if i < bytes.count, bytes[i] == 10 {
                        i += 1
                    }
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    static func isHex(_ b: UInt8) -> Bool {
        (b >= 48 && b <= 57) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)
    }

    static func decodeText(_ part: MimePart) -> String? {
        let data = Data(part.body)
        switch part.charset ?? "utf-8" {
        case "gbk", "gb2312", "gb18030":
            return String(data: data, encoding: EncodedWord.gb18030)
        case "iso-8859-1", "latin1":
            return String(data: data, encoding: .isoLatin1)
        default:
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: EncodedWord.gb18030) // 容错：缺省声明但实为 GBK
        }
    }

    // MARK: - 附件判定

    static func filename(of headers: [String: String], params: [String: String]) -> String? {
        if let disp = headers["content-disposition"],
           disp.lowercased().hasPrefix("attachment"),
           let name = parameterValue(disp, key: "filename") {
            return EncodedWord.decode(name)
        }
        if let name = params["name"] { return EncodedWord.decode(name) }
        return nil
    }

    static func parameterValue(_ header: String, key: String) -> String? {
        for seg in header.split(separator: ";").dropFirst() {
            let kv = seg.split(separator: "=", maxSplits: 1)
            guard kv.count == 2,
                  kv[0].trimmingCharacters(in: .whitespaces).lowercased() == key else { continue }
            var v = kv[1].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            return v
        }
        return nil
    }

    static func isAttachment(_ part: MimePart) -> Bool {
        if part.filename != nil { return true }
        if part.headers["content-disposition"]?.lowercased().hasPrefix("attachment") == true { return true }
        let main = part.contentType.split(separator: "/").first.map(String.init) ?? ""
        return ["image", "audio", "video", "application"].contains(main)
    }
}
