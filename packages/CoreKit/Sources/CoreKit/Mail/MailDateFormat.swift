import Foundation

/// 邮件日期解析与规范化（JOURNEY-020）：**ISO8601 优先，RFC2822 原文兜底**。
/// 入库路径统一规范化为 ISO8601 字符串（字符串排序 = 时间序，列表 ORDER BY 依赖此性质）；
/// 解析失败的原文原样保留（显示层兜底）。线程安全（RFC2822 formatter 加锁）。
public enum MailDateFormat {

    /// ISO8601（线程安全，Apple 文档保证）。
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// RFC2822（"Fri, 7 Nov 2026 10:00:00 +0000"，DateFormatter 非并发安全 → 加锁）。
    private final class RFC2822Formatter: @unchecked Sendable {
        let formatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
        private let lock = NSLock()
        func date(from raw: String) -> Date? {
            lock.lock(); defer { lock.unlock() }
            return formatter.date(from: raw)
        }
    }
    private static let rfc2822 = RFC2822Formatter()

    /// 双格式解析：ISO → RFC2822 →（宽容）剥 " (UTC)" 类时区注释后缀再试。
    public static func parse(_ raw: String) -> Date? {
        if let d = iso.date(from: raw) { return d }
        if let d = rfc2822.date(from: raw) { return d }
        // "Sat, 07 Nov 2026 10:20:00 +0000 (UTC)" 这类带注释的变体（实测 Outlook）
        if let open = raw.lastIndex(of: "("), raw.hasSuffix(")") {
            let trimmed = String(raw[..<open]).trimmingCharacters(in: .whitespaces)
            return rfc2822.date(from: trimmed)
        }
        return nil
    }

    /// 入库规范化：可解析 → ISO8601 字符串；不可解析 → 原文兜底；空 → nil。
    public static func normalized(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = parse(raw) { return iso.string(from: d) }
        return raw
    }
}
