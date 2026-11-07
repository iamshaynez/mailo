# MAIL · 协议域用例（v1：稳定主键）

> 归属：`packages/CoreKit/Sources/CoreKit/Mail`
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
