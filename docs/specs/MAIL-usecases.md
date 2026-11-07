# MAIL · 协议域用例

> 归属：`packages/CoreKit/Sources/CoreKit/Mail`（稳定主键）与 `packages/MailProtoKit`（协议解析与假服务器）
> 背景：IMAP UID 会因 UIDVALIDITY 重置而失稳，邮件与分类的关联必须用稳定主键（基线 v3 §3）。

## MAIL-001 稳定主键与 UID 无关且规范化
- **Given** Message-ID 为 `"<ABC-123@smtp.corp.com>"`（带尖括号、大小写混合），账号指纹 `acct-9`
- **When** 构造稳定主键
- **Then** 主键仅由 `规范化Message-ID + 账号指纹` 决定（尖括号剥离、小写、去内部空白）；同一封邮件从不同文件夹/不同 UID 读出，主键相同
- **Status**: green
- **Tests**: `mail_001_stable_id_normalizes_and_ignores_uid`

## MAIL-002 Message-ID 缺失时的确定性 fallback
- **Given** 一封无 Message-ID 的邮件（部分老服务器/转发产生）
- **When** 以相同 From/Date/Subject 两次构造主键
- **Then** 两次结果一致（确定性哈希）；任一输入不同则主键不同
- **Status**: green
- **Tests**: `mail_002_fallback_id_is_deterministic`

## MAIL-003 FETCH 响应解析（ENVELOPE/FLAGS/UID）
- **Given** 假服务器返回 `* 3 FETCH (UID 42 FLAGS (\Seen) INTERNALDATE "07-Nov-2026 10:00:00 +0000" ENVELOPE ("Wed, 7 Nov 2026 10:00:00 +0000" "Re: Contract" (("Sarah" NIL "sarah" "wave.co")) ...))`
- **When** 解析该 untagged 响应
- **Then** 得出 uid=42、flags 含 \Seen、subject="Re: Contract"、from 地址 sarah@wave.co、INTERNALDATE 可读
- **Status**: green
- **Tests**: `mail_003_fetch_envelope_parse`

## MAIL-004 字面量跨行续传
- **Given** 响应含 IMAP 字面量（如 `BODY[HEADER] {29}\r\nMessage-ID: <a@b.c>\r\n`）
- **When** 解析
- **Then** 字面量字节精确拼接进结构，后续 token 继续正确解析
- **Status**: green
- **Tests**: `mail_004_literal_continuation`

## MAIL-005 RFC2047 encoded-word（含 GBK）
- **Given** 主题 `=?UTF-8?B?5L2g5aW9?=` 与 `=?GBK?B?083Tqg==?=`（GBK 编码的中文）
- **When** 解码
- **Then** 分别得到正确中文文本；未知编码时原样返回（不崩溃）
- **Status**: green
- **Tests**: `mail_005_encoded_word_gbk`

## MAIL-006 UIDVALIDITY 重置检测
- **Given** 会话曾以 uidValidity=7 SELECT 过 INBOX，再次 SELECT 时服务器返回 uidValidity=99
- **When** 同步引擎收到新状态
- **Then** 报告 `.uidValidityReset(folder:)` 事件（触发按稳定主键重拉，分类标注不丢失）
- **Status**: green
- **Tests**: `mail_006_uidvalidity_reset_event`

## MAIL-007 能力协商降级（QRESYNC→CONDSTORE→全量）
- **Given** 三个假服务器实例：CAPABILITY 分别含 QRESYNC、仅含 CONDSTORE、两者皆无
- **When** 同步引擎协商同步模式
- **Then** 分别选定 .qresync / .condstore / .full 模式
- **Status**: green
- **Tests**: `mail_007_capability_negotiation_fallback`

## MAIL-008 MIME 头解析（折叠续行/大小写）
- **Given** 头区含折叠续行（`Subject: foo\r\n bar`）与任意大小写键名（`MESSAGE-ID:`）
- **When** 解析头区
- **Then** 键统一小写、续行以单空格拼接、取值可查
- **Status**: green
- **Tests**: `mail_008_mime_header_folding`

## MAIL-009 multipart 遍历（含嵌套）
- **Given** multipart/mixed，内含 multipart/alternative（text/plain + text/html）与一个附件部分
- **When** 解析整个 MIME 树
- **Then** 叶子部分正确归类：plain/html 各一、附件一；嵌套结构被递归展开
- **Status**: green
- **Tests**: `mail_009_multipart_traversal`

## MAIL-010 传输编码解码（base64 / quoted-printable）
- **Given** CTE 为 base64 与 quoted-printable 的两个正文部分
- **When** 解码
- **Then** 字节精确还原（QP 含 =XX 与软换行 =）
- **Status**: green
- **Tests**: `mail_010_transfer_decoding`

## MAIL-011 邮件结构摘要（ParsedEmail）
- **Given** 一封完整邮件（头 + multipart 体 + 附件）
- **When** `MimeParser.parse`
- **Then** 得到 ParsedEmail：subject/from/date/messageId（缺头为 nil）、textBody、htmlBody、attachments（文件名+字节）；text/plain 优先于 html 作为 textBody
- **Status**: green
- **Tests**: `mail_011_parsed_email_summary`

## MAIL-012 正文字符集解码（GBK body）
- **Given** Content-Type 带 `charset=gbk` 的 base64 正文
- **When** 解析为文本
- **Then** 按 GB18030 超集正确解码中文；charset 缺省按 UTF-8 容错
- **Status**: green
- **Tests**: `mail_012_body_charset_gbk`

## MAIL-013 SMTP 会话状态机
- **Given** FakeSmtpServer（可注入失败码）
- **When** `SmtpClient.send` 走完整会话（EHLO→AUTH→MAIL FROM→RCPT→DATA→dot→QUIT）
- **Then** 命令序列与协议一致；任一步非 2xx/3xx 即抛错并中止
- **Status**: draft
- **Tests**: `mail_013_smtp_session_flow`

## MAIL-014 DATA 内容构造与点填充
- **Given** 正文含以 `.` 开头的行（`.hidden`）
- **When** 构造 DATA 块
- **Then** 头齐全（Message-ID/From/To/Subject/Date/MIME-Version/CTE）、点填充生效（`.` 行变 `..`）、以 `CRLF.CRLF` 终止
- **Status**: draft
- **Tests**: `mail_014_data_dot_stuffing`

## MAIL-015 账户配置与指纹
- **Given** 两个授权码账户（host+user 大小写/空白不一致 vs 完全不同的账户）
- **When** 派生账号指纹、做 JSON 编解码
- **Then** 规范化后同账户指纹相同；不同账户不同；**JSON 编码中不含授权码明文**（仅含 Keychain 引用）
- **Status**: draft
- **Tests**: `mail_015_account_fingerprint_and_secret_isolation`

## MAIL-016 IMAP 行读取器（TCP 分片容错）
- **Given** TLS 字节流以任意分片到达（半行/半字面量/多行粘连）
- **When** 逐片喂入 ImapLineReader
- **Then** 每凑齐一条完整逻辑行（含 RFC3501 字面量整体）即吐出，字节精确无损
- **Status**: draft
- **Tests**: `mail_016_line_reader_fragmented`

## MAIL-017 XOAUTH2 SASL 载荷构造
- **Given** 用户名与 OAuth access token
- **When** 构造 XOAUTH2 初始响应
- **Then** base64(`user=<u>\x01auth=Bearer <t>\x01\x01`) 精确生成；服务器拒绝后的空响应构造正确
- **Status**: draft
- **Tests**: `mail_017_xoauth2_sasl`

## MAIL-018 SMTP 多行应答解析
- **Given** `250-line1` / `250-line2` / `250 final` 序列
- **When** 解析
- **Then** 归并为单一 SmtpReply（code=250，lines=3）；`250-` 为续行、`250 ` 为终行
- **Status**: draft
- **Tests**: `mail_018_smtp_multiline_reply`

## MAIL-019 生产传输类型就位（编译级门禁）
- **Given** Network.framework 可用（Apple 平台）
- **When** 实例化 TcpImapTransport / TcpSmtpTransport（993/465 TLS）
- **Then** 类型符合 ImapTransport/SmtpTransport 端口、连接超时可配（真实联调需用户环境，CI 验证编译与构造）
- **Status**: draft
- **Tests**: `mail_019_production_transports_instantiate`

## MAIL-020 设备码流响应解析（本地联调授权）
- **Given** Microsoft device code 端点的三类 JSON 响应（下发码 / 轮询等待 / 授权成功或拒绝）
- **When** 解析
- **Then** 下发码解析出 device_code/user_code/URI/interval；`authorization_pending` 归为 pending；有 access_token 归为 granted；显式 error 归为 denied（含描述）；坏 JSON 抛错
- **Status**: draft
- **Tests**: `mail_020_device_code_flow_parsing`
