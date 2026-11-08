import Foundation

/// 发件人地址解析（MAIL-023）：真实邮件 From 头形态净化。
/// `"Sarah Chen" <sarah@wave.co>` / `sarah@wave.co` / `sarah@wave.co (注释)`
/// → 统一提取干净的 local@domain。分类管线的名单库/规则域名匹配依赖此净化。
public enum EmailAddress {
    public struct Parsed: Equatable, Sendable {
        public var local: String
        public var domain: String
        public var display: String?

        /// 干净地址（小写）。
        public var address: String { "\(local)@\(domain)" }
    }

    public static func parse(_ raw: String?) -> Parsed? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        // 剥尾部注释 `(comment)`
        if let open = s.lastIndex(of: "("), s.hasSuffix(")") {
            s = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        }

        // 显示名 + <addr>
        if let lt = s.lastIndex(of: "<"), s.hasSuffix(">") {
            let display = String(s[..<lt]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let inner = String(s[s.index(after: lt)..<s.index(before: s.endIndex)]).trimmingCharacters(in: .whitespaces)
            return components(inner, display: display.isEmpty ? nil : display)
        }
        return components(s, display: nil)
    }

    /// 只取域（小写）；无地址返回 nil。
    public static func domain(_ raw: String?) -> String? {
        parse(raw)?.domain
    }

    private static func components(_ address: String, display: String?) -> Parsed? {
        let parts = address.split(separator: "@")
        guard parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty,
              !parts[1].contains("<"), !parts[1].contains(">") else { return nil }
        return Parsed(local: parts[0].lowercased(), domain: parts[1].lowercased(), display: display)
    }
}
