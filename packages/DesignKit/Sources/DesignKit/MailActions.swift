import CoreKit
import Foundation

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-011 撰写预填 / JOURNEY-012 撤销）

/// 撰写草稿（JOURNEY-011）：Reply/Forward 预填的纯函数构造，壳层与命令面共用。
public struct ComposeDraft: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case compose
        case reply
        case forward
    }

    public let id = UUID()

    public var kind: Kind
    public var to: String
    public var subject: String
    public var body: String

    public init(kind: Kind = .compose, to: String = "", subject: String = "", body: String = "") {
        self.kind = kind
        self.to = to
        self.subject = subject
        self.body = body
    }

    /// Reply 主题：已有 Re:/Fwd: 前缀不重复叠加。
    public static func replySubject(_ subject: String?) -> String {
        prefixed("Re:", subject)
    }

    /// Forward 主题。
    public static func forwardSubject(_ subject: String?) -> String {
        prefixed("Fwd:", subject)
    }

    private static func prefixed(_ prefix: String, _ subject: String?) -> String {
        let base = subject?.isEmpty == false ? subject! : "(no subject)"
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix(prefix.lowercased()) { return trimmed }
        return "\(prefix) \(trimmed)"
    }

    /// Reply 正文：引用原邮件（hey 式简洁引用块）。
    public static func replyBody(quote: String?, from: String?) -> String {
        var out = "\n\n"
        if let from, !from.isEmpty { out += "On \(from) wrote:\n" }
        let lines = (quote ?? "").split(separator: "\n", omittingEmptySubsequences: false)
        out += lines.map { "> \($0)" }.joined(separator: "\n")
        return out
    }

    /// Forward 正文：转发头 + 原文。
    public static func forwardBody(quote: String?, from: String?, subject: String?, date: String?) -> String {
        var header = "\n\n---------- Forwarded message ----------\n"
        if let from, !from.isEmpty { header += "From: \(from)\n" }
        if let date, !date.isEmpty { header += "Date: \(date)\n" }
        if let subject, !subject.isEmpty { header += "Subject: \(subject)\n" }
        return header + "\n" + (quote ?? "")
    }
}

/// 可撤销动作（JOURNEY-012）：Set Aside / 纠正 / Screener 决策共用；
/// Edit 菜单 ⌘Z 消费（SwiftUI 场景内自管 undo 栈，v1 单步）。
public struct UndoableAction: @unchecked Sendable {
    public let label: String
    @MainActor let perform: @MainActor () -> Void

    public init(label: String, perform: @escaping @MainActor () -> Void) {
        self.label = label
        self.perform = perform
    }
}
