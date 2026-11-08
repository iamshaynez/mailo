import Foundation

/// IMAP 传输端口：发送命令，返回原始响应字节（含 \r\n 行与字面量）。
/// 生产实现走 Network.framework TCP；测试/引擎联调走 FakeImapServer（进程内）。
public protocol ImapTransport: Sendable {
    func send(_ command: ImapCommand) throws -> [UInt8]
}

/// v1 命令子集（按 M1 真实联调需要扩展）。
public enum ImapCommand: Equatable, Sendable {
    case capability
    case login(user: String, token: String)
    case select(folder: String)
    case fetchUid(range: String, items: String)
    case storeFlags(uid: Int, flags: [String])
    case noop

    public var wire: String {
        // 调用方负责 tag 前缀
        switch self {
        case .capability: return "CAPABILITY"
        case .login(let u, let t): return "LOGIN \"\(u)\" \"\(t)\""
        case .select(let f): return "SELECT \"\(f)\""
        case .fetchUid(let r, let i): return "UID FETCH \(r) \(i)"
        case .storeFlags(let uid, let flags): return "UID STORE \(uid) +FLAGS.SILENT (\(flags.joined(separator: " ")))"
        case .noop: return "NOOP"
        }
    }
}
