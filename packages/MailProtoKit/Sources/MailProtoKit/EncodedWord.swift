import Foundation

/// RFC2047 encoded-word 解码：=?charset?B/Q?data?=
/// charset 大小写不敏感；GBK/GB2312 统一按 GB18030 超集解码（国内服务器常见，MAIL-005）。
public enum EncodedWord {
    public static func decode(_ raw: String) -> String {
        // PLACEHOLDER (red phase)
        return raw
    }
}
