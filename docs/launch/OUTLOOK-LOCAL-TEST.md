# Outlook 本地联调 · Step by Step（OUTLOOK-LOCAL-TEST）

> 用你自己的 Outlook.com 邮箱实测 Mailo 的生产传输层：
> **TLS 直连 → XOAUTH2 认证 → SELECT → FETCH → ENVELOPE 解析**。
> 全程命令行完成，token 只存活于探针进程内存（不写盘、不入库）。
> 详细背景：[03-microsoft-entra-outlook.md](03-microsoft-entra-outlook.md)。

## 前置检查（一次性）

```bash
swift --version   # 需要 6.x；若 manifest 报错 → 本机 CLT 损坏，先执行：
# sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install
# （或装完整 Xcode 后 sudo xcode-select -s /Applications/Xcode.app）
```

## 第 1 步 · 注册 Entra 应用拿 Client ID（免费，~5 分钟，只需一次）

1. 打开 https://entra.microsoft.com → 登录任意 Microsoft 账号（个人 MSA 即可）
2. **身份 → 应用程序 → 应用注册 → 新建注册**
3. 名称 `MailoProbe`；**受支持的账户类型选第 3 项**
   （"任何组织目录中的账户 + 个人 Microsoft 账户"——多租户 + MSA）
4. 重定向 URI **不填**（设备码流不需要）
5. 注册后复制 **应用程序(客户端) ID**——这就是 `--client` 参数

> 权限无需预配置：IMAP.AccessAsUser.All 属委托权限，用户在设备码登录时现场同意。

## 第 2 步 · 一条命令跑通全链路

```bash
cd /path/to/mailo
swift run --package-path packages/MailProtoKit MailoProbe \
  --client <你的CLIENT_ID> --user <你的邮箱>@outlook.com
```

探针会依次做（每步有 ✓ 输出）：

```
① 请求设备码 → 打开 https://microsoft.com/devicelogin 输入屏幕上的代码
   （用你的 Outlook 账号登录并同意）
② 轮询令牌（每 5 秒）→ ✓ 授权成功
③ TLS 连 outlook.office365.com:993 → XOAUTH2 认证 → ✓
④ CAPABILITY → 服务器能力清单
⑤ SELECT INBOX → ✓ n EXISTS
⑥ FETCH 最近 3 封 → 逐封打印 [UID] 主题 — 发件人 [Flags]
✅ 全链路验证通过
```

常用变体：`--count 10`（多拉几封）、`--folder "Junk"`（换文件夹）、
`--imap-host`（打自建/其他服务器）。

## 第 3 步 · 验证清单

- [ ] 设备码页同意后，探针 10 秒内出 `✓ 授权成功`
- [ ] `✓ 已认证`（XOAUTH2 被 outlook.office365.com 接受）
- [ ] EXISTS 数与你邮箱实际件数一致
- [ ] 最近邮件的主题/发件人正确显示（ENVELOPE 解析真实数据）
- [ ] 中文主题正常（RFC2047 解码路径）

## 排障表

| 症状 | 原因与处理 |
|---|---|
| `AADSTS700016`（应用未找到） | client id 抄错，或应用注册在别的租户 |
| `AADSTS7000215`（无效客户端密钥） | 用了 client secret 流——探针不需要，检查是否填错参数 |
| `AADSTS65001`（未同意权限） | 登录时未勾选同意；重跑，或 Entra 应用"API 权限"里手动加 IMAP.AccessAsUser.All |
| 认证后 FETCH 报 `AUTHENTICATE failed` | token audience 不对：确认走的是本工具（consumers 端点 + office365 scope） |
| `timeout("connect")` | 本地网络到 993 端口不通（代理/防火墙） |
| 授权成功但立即 `closed` | 令牌过期（1 小时）——重跑探针重新授权即可 |

## 安全注意

- Client ID 不是机密（公开 client），但**设备码页务必只输探针显示的代码**；
- token 只在进程内存；探针永不写文件；仓库规则照旧：任何凭证不入库。
