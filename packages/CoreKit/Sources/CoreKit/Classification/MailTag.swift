import Foundation

/// 桶内子分组标签（CLS-012/013）：HEY「桶」之下的用户级细分。
/// 单选语义——一封邮件同桶内至多一个组；组名仅做空白规范化（保留大小写显示）。
public struct MailTag: Hashable, Sendable, Codable {
    public var name: String

    public init(_ name: String) {
        self.name = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
