# OAUTH · 授权与凭证域用例（AuthKit）

> 归属：`packages/AuthKit`。Gmail/Outlook 的 IMAP+XOAUTH2 所需配置常量、凭证保管端口、token 会话语义。
> 真实授权 UI 流（AppAuth/ASWebAuthenticationSession）挂在 app 层，等正式 client id 注册后接入（docs/launch/02、03）。

## OAUTH-001 服务商授权配置常量
- **Given** Gmail 与 Outlook 的 IMAP/SMTP 端点与 scope
- **When** 读取 OAuthProviderConfig
- **Then** Gmail scope 为全量 `https://mail.google.com/`（基线 §4.1 决策点记录在案）；Outlook 为 IMAP.AccessAsUser.All + SMTP.Send；redirect scheme 与 bundle id 一致派生
- **Status**: draft
- **Tests**: `oauth_001_provider_constants`

## OAUTH-002 凭证保管（端口语义）
- **Given** CredentialVault 端口（生产=Keychain，测试=InMemory）
- **When** 存/取/删 token
- **Then** 按 secretRef 往返一致；删除后取不到；枚举所有键不返回明文值
- **Status**: draft
- **Tests**: `oauth_002_credential_vault_semantics`

## OAUTH-003 token 会话刷新判定
- **Given** OAuthSession（expiry 已知）
- **When** needsRefresh(now)
- **Then** 过期前 60s 内即需刷新（提前量避免竞态）；过期已久必刷
- **Status**: draft
- **Tests**: `oauth_003_session_refresh_window`

## OAUTH-004 Keychain 生产实现（真实读写）
- **Given** Security.framework Keychain（CI macOS runner 的解锁 keychain）
- **When** KeychainVault 存/取/删/枚举
- **Then** 语义与端口契约一致（OAUTH-002 同款断言，真实 SecItem 路径）
- **Status**: draft
- **Tests**: `oauth_004_keychain_vault_real`
