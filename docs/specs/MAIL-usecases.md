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
- **Status**: draft
- **Tests**: `mail_003_fetch_envelope_parse`

## MAIL-004 字面量跨行续传
- **Given** 响应含 IMAP 字面量（如 `BODY[HEADER] {29}\r\nMessage-ID: <a@b.c>\r\n`）
- **When** 解析
- **Then** 字面量字节精确拼接进结构，后续 token 继续正确解析
- **Status**: draft
- **Tests**: `mail_004_literal_continuation`

## MAIL-005 RFC2047 encoded-word（含 GBK）
- **Given** 主题 `=?UTF-8?B?5L2g5aW9?=` 与 `=?GBK?B?083Tqg==?=`（GBK 编码的中文）
- **When** 解码
- **Then** 分别得到正确中文文本；未知编码时原样返回（不崩溃）
- **Status**: draft
- **Tests**: `mail_005_encoded_word_gbk`

## MAIL-006 UIDVALIDITY 重置检测
- **Given** 会话曾以 uidValidity=7 SELECT 过 INBOX，再次 SELECT 时服务器返回 uidValidity=99
- **When** 同步引擎收到新状态
- **Then** 报告 `.uidValidityReset(folder:)` 事件（触发按稳定主键重拉，分类标注不丢失）
- **Status**: draft
- **Tests**: `mail_006_uidvalidity_reset_event`

## MAIL-007 能力协商降级（QRESYNC→CONDSTORE→全量）
- **Given** 三个假服务器实例：CAPABILITY 分别含 QRESYNC、仅含 CONDSTORE、两者皆无
- **When** 同步引擎协商同步模式
- **Then** 分别选定 .qresync / .condstore / .full 模式
- **Status**: draft
- **Tests**: `mail_007_capability_negotiation_fallback`
