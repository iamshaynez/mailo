# 02 · Google OAuth（Gmail 接入）：测试模式 → 正式验证 → CASA

> 目的：Gmail 用户接入的唯一通道（Gmail 无授权码）。**restricted scope 公开发布必须过 OAuth 验证 + CASA 安全评估（每年复审）**。
> 分两个阶段：M0 用**测试模式**当天可开发内测（100 测试用户上限、token 7 天过期）；M2 提交正式验证。
> 信息查证时间：2026-11，以 Google 官方文档为准。

## ⚠️ 先做一个 scope 决策（影响 consent 屏与用户信任）

| 路线 | Scope | 说明 |
|---|---|---|
| IMAP + XOAUTH2 | `https://mail.google.com/`（全量：读写发送永久删除） | **IMAP/SMTP 只认这一个 scope**，`gmail.readonly` 等窄权限对 IMAP 无效 |
| Gmail REST API | `gmail.readonly` / `gmail.modify` / `gmail.send`（最小权限） | 需要单独的 REST 适配器，与"协议栈收敛 IMAP"的架构决定冲突 |

两条路**都是 restricted scope、都要 CASA**，验证负担相同；差别只在用户看到的授权屏：IMAP 路线显示"永久删除所有邮件的权限"，REST 路线可以窄到只读+发送。
**当前方案（IMAP 单栈）按上表第一行执行；M1 结束前用真实 consent 屏截图复核一次，若用户流失风险不可接受，Gmail 单独走 REST 适配器（架构上已留端口，成本可控）。**

## Phase 1 · M0 第一天：项目 + 测试模式（当天可用）

1. 打开 https://console.cloud.google.com → 新建项目（如 `mailo-prod`）
2. **API 和服务 → OAuth 同意屏幕（OAuth consent screen）**：
   - User Type 选 **External**（外部）
   - App information：应用名 Mailo、支持邮箱、logo（会展示在授权屏，放正式 logo）
   - App domain：首页（04 文档的 URL）、隐私政策链接（04 文档的 URL）—— 此处先填上，正式验证时必查
3. **Scopes**：添加 `https://mail.google.com/`（或按上表决策结果）
4. **Test users**：把内测同事/自己的 Gmail 地址加进去（上限 100）
5. **凭据 → 创建凭据 → OAuth 客户端 ID → iOS**：填 bundle id（与 01 文档定的一致）。纯本地客户端无需 secret。Android 二期再来加一条 Android 类型的 client（包名+SHA1）
6. 记录 **Client ID** 进配置（`GoogleService-Info` 由 Google 自动生成，iOS 工程引用）

**测试模式的三个已知摩擦（内测预期管理用）**：
- 每个测试用户要手动加入白名单才能授权
- 授权屏显示黄色"未验证应用"警告（内测期正常，点"高级→继续"可过）
- refresh token **7 天过期**，内测用户每周重登一次 —— 正式验证后消失

## Phase 2 · M2：提交正式验证（4-6 周）

提交前备齐（缺一被退回重来，周期重置）：

1. **隐私政策 URL** 与**首页 URL** 已上线且 HTTPS（见 04 文档）
2. **演示视频**（YouTube，unlisted 即可）：完整走一遍 Gmail 授权 → 展示每个 restricted scope 具体如何使用（收信列表、发信、设置页），Google 审核员靠它判断用途，时长 2-3 分钟、带解说字幕
3. 每个 scope 的**用途说明**（justification）：一句话说清"为什么需要"，与实际功能一致
4. （若用自定义域名）Search Console 完成域名所有权验证

提交路径：OAuth 同意屏幕页 → **提交以进行验证（Submit for verification）**。
之后 Google 会发邮件要求进行安全评估（CASA），进入 Phase 3。

**Limited Use 豁免**：≤100 用户且符合条件可申请免评估 —— 商业产品不适用，知道存在即可。

## Phase 3 · CASA Tier 2 自扫（费用主体，$500-4500/年）

1. 收到 Google 的 assessment 要求邮件后，前往 [Google CASA 页](https://cloud.google.com/docs/security/compliance/casa) 上的 **Authorized Labs 名单**（TAC Security、OSTEC、Imunify360 等，费用各异，自行比价）
2. 选 lab 购买 **Tier 2 self-scan** 套餐 → lab 提供扫描工具 + 问卷
3. 对我们这种**纯本地客户端**（无服务器、无数据传输），评估面集中在：
   - OAuth token 保管（必须 Keychain / iOS Secure Enclave，绝不落明文磁盘）
   - 本地数据加密（SQLite 加密、钥匙串访问组）
   - 传输 TLS、无第三方数据共享（隐私政策与 04 文档表述一致）
4. 扫描+问卷通过 → lab 出具报告 → 提交 Google → consent 屏摘掉警告、测试用户白名单与 7 天 token 限制解除

**年审**：CASA 报告 12 个月有效，续费重扫，日历记死。

## 完成标志（DoD）

- [ ] 测试模式：100 白名单用户可完整走通 Gmail 收发（M0 周）
- [ ] 正式：consent 屏无"未验证"警告，任意 Gmail 用户可授权（M2-M3）
- [ ] CASA 报告归档 + 年审日期入日历

## 常见坑（都真实发生过）

- 演示视频没展示 scope 实际用途 → 直接退回，白等 3 周
- 隐私政策里没写 **Google API Services User Data Policy / Limited Use 声明** → 验证不通过（04 文档已内置该段）
- 首页是 404 或"建设中" → 退回
- scope justification 写"未来可能用于 AI 功能" → 退回（只写当前实际用途）

## 参考

- [Google: restricted scope 验证要求](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [Google: CASA Tier 2 流程](https://cloud.google.com/docs/security/compliance/casa)
- [Gmail API scopes（restricted 清单）](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Gmail IMAP 只认全量 scope 的官方说明与社区讨论](https://issuetracker.google.com/issues/277134811)
