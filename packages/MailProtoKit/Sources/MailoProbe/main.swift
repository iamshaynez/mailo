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
    var account: DeviceCodeFlow.MicrosoftAccount = .personal

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
            case "--account":
                guard let acc = DeviceCodeFlow.MicrosoftAccount(rawValue: value.lowercased()) else { return nil }
                a.account = acc
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

func acquireToken(clientId: String, account: DeviceCodeFlow.MicrosoftAccount) throws -> String {
    print("① 请求设备码（租户 \(account.tenant)）…")
    let codeData = try httpPost(DeviceCodeFlow.deviceCodeURL(account: account), form: [
        "client_id": clientId,
        "scope": DeviceCodeFlow.mailScope(account: account),
    ])
    // 失败时把微软原始响应打出来（AADSTS 错误码直接可见，不再吞成 missingField）
    guard let req = try? DeviceCodeFlow.parseDeviceCodeResponse(codeData) else {
        FileHandle.standardError.write(Data(
            "✗ 设备码下发失败，服务器原始响应:\n\(String(data: codeData, encoding: .utf8) ?? "<binary>")\n".utf8))
        exit(2)
    }
    print("")
    print("  ┌──────────────────────────────────────────────────┐")
    print("  │  在浏览器打开: \(req.verificationURI)")
    print("  │  输入代码:     \(req.userCode)")
    print("  │  使用账户登录后回到这里（有效期 \(req.expiresIn / 60) 分钟）")
    print("  └──────────────────────────────────────────────────┘")
    print("")

    let deadline = Date().addingTimeInterval(TimeInterval(req.expiresIn))
    let interval = req.interval
    while Date() < deadline {
        sleep(UInt32(max(1, interval)))
        print("② 轮询令牌 …")
        let tokenData = try httpPost(DeviceCodeFlow.tokenURL(account: account), form: [
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
    let selectBytes = try transport.send(.select(folder: folder))
    let select = String(decoding: selectBytes, as: UTF8.self)
    guard select.contains(" OK ") else {
        FileHandle.standardError.write(Data("✗ SELECT 失败:\n\(select)\n".utf8)); exit(3)
    }
    let info = SelectState.parse(selectBytes)
    print("✓ \(info.exists) EXISTS · UIDNEXT \(info.uidNext)")

    // 只拉最近 N 封（窄区间），绝不全量 FETCH 大邮箱
    let range = info.recentRange(count: count)
    print("⑥ UID FETCH \(range)（最近 \(count) 封，UID FLAGS ENVELOPE）…")
    let fetchBytes = try transport.send(.fetchUid(range: range, items: "(UID FLAGS ENVELOPE)"))
    let lines = try ImapParser.parse(fetchBytes)
    var fetched: [FetchData] = []
    for line in lines {
        if let fd = FetchData.extract(from: line) { fetched.append(fd) }
    }
    let recent = fetched.suffix(count)
    if recent.isEmpty {
        print("（区间无邮件——邮箱可能为空）")
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
      swift run MailoProbe --client <ENTRA_CLIENT_ID> --user <you@outlook.com> \
        [--account personal|organizational] [--folder INBOX] [--count 3] [--imap-host outlook.office365.com]

    个人账户(@outlook/@hotmail)默认 personal；M365 工作账户用 --account organizational。
    前置: docs/launch/OUTLOOK-LOCAL-TEST.md（注册应用 + 开启"允许公共客户端流"）
    """)
    exit(1)
}()

do {
    let token = try acquireToken(clientId: args.clientId, account: args.account)
    try probe(user: args.user, token: token, host: args.imapHost, folder: args.folder, count: args.count)
} catch let e as TransportError {
    FileHandle.standardError.write(Data("✗ 传输错误: \(e)\n".utf8)); exit(4)
} catch {
    FileHandle.standardError.write(Data("✗ \(error)\n".utf8)); exit(5)
}
