import Foundation
import MailProtoKit

// MailoProbe —— Outlook 本地联调探针（docs/launch/OUTLOOK-LOCAL-TEST.md）
//
//   一条命令完成：设备码授权 → XOAUTH2 连接 outlook.office365.com → SELECT INBOX → 拉最近 N 封
//
//   swift run --package-path packages/MailoProbe MailoProbe --client <CLIENT_ID> --user <you@outlook.com>
//
// token 仅存活于本进程内存，不写任何文件。

struct ProbeArgs {
    var clientId: String = ""
    var user: String = ""
    var folder: String = "INBOX"
    var count: Int = 3
    var imapHost: String = "outlook.office365.com"

    static func parse(_ argv: [String]) -> ProbeArgs? {
        var a = ProbeArgs()
        var i = 0
        while i < argv.count {
            let key = argv[i]
            guard i + 1 < argv.count else { return nil }
            let value = argv[i + 1]
            switch key {
            case "--client": a.clientId = value
            case "--user": a.user = value
            case "--folder": a.folder = value
            case "--count": a.count = Int(value) ?? 3
            case "--imap-host": a.imapHost = value
            default: return nil
            }
            i += 2
        }
        return a.clientId.isEmpty || a.user.isEmpty ? nil : a
    }
}

// URL 会话的同步包装（探针是命令行工具，阻塞 IO 无妨）
func httpPost(_ url: URL, form: [String: String]) throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)" }
        .joined(separator: "&").data(using: .utf8)
    let sem = DispatchSemaphore(value: 0)
    var out: Data?
    var err: Error?
    URLSession.shared.dataTask(with: request) { data, _, error in
        out = data; err = error; sem.signal()
    }.resume()
    guard sem.wait(timeout: .now() + 30) == .success else { throw TransportError.timeout("http") }
    if let e = err { throw e }
    return out ?? Data()
}

func acquireToken(clientId: String) throws -> String {
    print("① 请求设备码 …")
    let codeData = try httpPost(DeviceCodeFlow.microsoftDeviceCodeURL, form: [
        "client_id": clientId,
        "scope": DeviceCodeFlow.microsoftMailScope,
    ])
    let req = try DeviceCodeFlow.parseDeviceCodeResponse(codeData)
    print("")
    print("  ┌──────────────────────────────────────────────────┐")
    print("  │  在浏览器打开: \(req.verificationURI)")
    print("  │  输入代码:     \(req.userCode)")
    print("  │  使用账户登录后回到这里（有效期 \(req.expiresIn / 60) 分钟）")
    print("  └──────────────────────────────────────────────────┘")
    print("")

    let deadline = Date().addingTimeInterval(TimeInterval(req.expiresIn))
    var interval = req.interval
    while Date() < deadline {
        sleep(UInt32(max(1, interval)))
        print("② 轮询令牌 …")
        let tokenData = try httpPost(DeviceCodeFlow.microsoftTokenURL, form: [
            "client_id": clientId,
            "device_code": req.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        switch DeviceCodeFlow.parseTokenResponse(tokenData) {
        case .granted(let token):
            print("✓ 授权成功（token 已入内存，不入盘）")
            return token
        case .pending:
            continue
        case .denied(let error, let description):
            FileHandle.standardError.write(Data("✗ 授权被拒: \(error) — \(description)\n".utf8))
            exit(2)
        }
    }
    FileHandle.standardError.write(Data("✗ 设备码超时\n".utf8))
    exit(2)
}

func probe(user: String, token: String, host: String, folder: String, count: Int) throws {
    print("③ TLS 连接 \(host):993 并 XOAUTH2 认证 …")
    let transport = TcpImapTransport(host: host, port: 993, connectTimeout: 15)
    try transport.connect(method: .xoauth2(user: user, accessToken: token))
    print("✓ 已认证")

    print("④ CAPABILITY …")
    let caps = String(decoding: try transport.send(.capability), as: UTF8.self)
    print(caps.split(separator: "\r\n").prefix(2).joined(separator: "\n"))

    print("⑤ SELECT \(folder) …")
    let select = String(decoding: try transport.send(.select(folder: folder)), as: UTF8.self)
    guard select.contains(" OK ") else {
        FileHandle.standardError.write(Data("✗ SELECT 失败:\n\(select)\n".utf8)); exit(3)
    }
    if let exists = select.split(whereSeparator: \.isNewline).first(where: { $0.contains("EXISTS") }) {
        print("✓ \(exists.trimmingCharacters(in: .whitespaces))")
    }

    print("⑥ FETCH 最近 \(count) 封（UID FLAGS ENVELOPE）…")
    let fetchBytes = try transport.send(.fetchUid(range: "1:*", items: "(UID FLAGS ENVELOPE)"))
    let lines = try ImapParser.parse(fetchBytes)
    var fetched: [FetchData] = []
    for line in lines {
        if let fd = FetchData.extract(from: line) { fetched.append(fd) }
    }
    let recent = fetched.suffix(count)
    if recent.isEmpty {
        print("（邮箱为空）")
    }
    for fd in recent.reversed() {
        let flags = fd.flags.isEmpty ? "-" : fd.flags.joined(separator: ",")
        print("  · [\(fd.uid)] \(fd.subject ?? "(无主题)")  —  \(fd.fromAddress ?? "?")  [\(flags)]")
    }
    print("")
    print("✅ 全链路验证通过：TLS → XOAUTH2 → SELECT → FETCH → ENVELOPE 解析")
}

let args = ProbeArgs.parse(Array(CommandLine.arguments.dropFirst())) ?? {
    print("""
    MailoProbe — Outlook 本地联调探针

    用法:
      swift run MailoProbe --client <ENTRA_CLIENT_ID> --user <you@outlook.com> [--folder INBOX] [--count 3] [--imap-host outook.office365.com]

    前置: 先按 docs/launch/03 注册 Entra 应用拿 client id（免费，5 分钟）。
    流程: docs/launch/OUTLOOK-LOCAL-TEST.md
    """)
    exit(1)
}()

do {
    let token = try acquireToken(clientId: args.clientId)
    try probe(user: args.user, token: token, host: args.imapHost, folder: args.folder, count: args.count)
} catch let e as TransportError {
    FileHandle.standardError.write(Data("✗ 传输错误: \(e)\n".utf8)); exit(4)
} catch {
    FileHandle.standardError.write(Data("✗ \(error)\n".utf8)); exit(5)
}
