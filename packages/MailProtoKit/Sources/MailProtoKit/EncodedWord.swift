import Foundation

/// RFC2047 encoded-word 解码：=?charset?B/Q?data?=
/// charset 大小写不敏感；GBK/GB2312/GB18030 统一按 GB18030 超集解码（国内服务器常见，MAIL-005）。
public enum EncodedWord {
    /// GB18030（GBK/GB2312 的超集）。Apple 平台通过 CF 编码桥接。
    public static let gb18030: String.Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    private static let wordPattern = "=\\?([^?]+)\\?([bBqQ])\\?([^ ?]*)\\?="

    public static func decode(_ raw: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else { return raw }
        let ns = raw as NSString
        var result = ""
        var cursor = 0
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            guard m.range.location >= cursor else { continue } // 防御重叠匹配
            let charset = ns.substring(with: m.range(at: 1)).lowercased()
            let enc = ns.substring(with: m.range(at: 2)).uppercased()
            let data = ns.substring(with: m.range(at: 3))
            // 未识别的 charset/编码：跳过替换，整词原样保留（不崩溃，MAIL-005）
            guard let bytes = decodeData(data, encoding: enc),
                  let text = decodeBytes(bytes, charset: charset) else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            result += text
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func decodeData(_ data: String, encoding: String) -> [UInt8]? {
        switch encoding {
        case "B":
            var s = data
            while !s.isEmpty && s.count % 4 != 0 { s += "=" }
            guard let d = Data(base64Encoded: s) else { return nil }
            return [UInt8](d)
        case "Q":
            var out: [UInt8] = []
            var chars = Array(data)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "=" {
                    guard i + 2 < chars.count,
                          let b = UInt8(String(chars[(i + 1)...(i + 2)]), radix: 16) else { return nil }
                    out.append(b)
                    i += 3
                } else if c == "_" {
                    out.append(UInt8(ascii: " "))
                    i += 1
                } else {
                    out.append(c.asciiValue ?? UInt8(ascii: "?"))
                    i += 1
                }
            }
            return out
        default:
            return nil
        }
    }

    private static func decodeBytes(_ bytes: [UInt8], charset: String) -> String? {
        let data = Data(bytes)
        switch charset {
        case "utf-8", "utf8", "us-ascii", "ascii":
            return String(data: data, encoding: .utf8)
        case "gbk", "gb2312", "gb18030":
            return String(data: data, encoding: gb18030)
        case "iso-8859-1", "latin1":
            return String(data: data, encoding: .isoLatin1)
        default:
            return nil
        }
    }
}
