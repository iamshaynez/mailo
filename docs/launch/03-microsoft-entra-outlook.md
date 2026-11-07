# 03 · Microsoft Entra 应用注册（Outlook / MSA 接入）

> 目的：Outlook.com（个人 MSA）与 Microsoft 365（组织）邮箱接入。基本认证已死，必须 OAuth2；
> 我们走 **IMAP/SMTP + XOAUTH2**（服务器 `outlook.office365.com` / `smtp.office365.com`）。
> 应用注册本身免费、当天完成；**政策核实**（见末尾）是本线的真正交付物。
> 信息查证时间：2026-11，以 Microsoft Learn 为准。

## Phase 1 · 应用注册（M0 当天）

1. 打开 https://entra.microsoft.com （用任意 Microsoft 账号登录，免费层即可）
2. **身份 → 应用程序 → 应用注册 → 新建注册**：
   - 名称：`Mailo`
   - 受支持的账户类型（**关键项**）：
     **"任何组织目录中的账户（多租户）+ 个人 Microsoft 账户（Skype、Xbox 等）"**
     —— 即 multitenant + personal MSA，同时覆盖 outlook.com/hotmail 与企业 M365
   - 重定向 URI：选 **"公共客户端/本机(移动和桌面)"**，填 `msauth.<bundle.id>://auth`（bundle id 与 01 文档一致；MSAL iOS SDK 会自动生成同格式 URI）
3. 注册后记录三样进配置：
   - **Application (client) ID** —— 代码里用它
   - Authority：混合受众用 `https://login.microsoftonline.com/common`
   - （公开客户端**不需要** client secret，别生成）
4. **API 权限 → 添加权限 → 我的组织使用的 API → Office 365 Exchange Online**：
   - 委托权限（Delegated）：`IMAP.AccessAsUser.All`、`SMTP.Send`
   - 点 **"代表 <租户> 授予管理员同意"**（仅影响自己租户的测试账号；个人 MSA 用户授权发生在用户首登时）
5. 真机验证：用测试 MSA 账号走 MSAL 登录 → 拿 access token → IMAP `AUTHENTICATE XOAUTH2` 连 `outlook.office365.com:993` 收一封、SMTP 发一封。**这一步通了，本线 Phase 1 完成。**

## Phase 2 · Publisher 验证（建议做，视核实结果定）

未验证发布者的 consent 屏会显示"未验证的发布者"警示，对邮件类高信任品类转化不利。

1. 前提：组织主体（同 01 文档的公司）+ [Partner Center](https://partner.microsoft.com/dashboard) 开发者账户（按指引完成组织验证：法人信息、银行/税务信息视账户类型）
2. Partner Center 完成验证后回到 Entra → 应用注册 → Mailo → **品牌发布 → 已验证发布者 ID** 关联
3. 周期数周、以注册流程实际收费为准（组织验证可能涉及一次性费用，页面会明示）

**何时可以跳过**：若仅内测 / 政策核实结论显示当前不受强制。

## Phase 3 · 政策核实（本线真正交付物，M0-M1 持续）

2024 年起 Outlook.com 第三方客户端生态持续收紧（基本认证下线、部分第三方客户端被限流或要求迁移 Graph 的社区报告持续出现）。**在动 Outlook 适配器代码之前**，完成以下核实并记录结论：

1. 查 [Microsoft Graph 权限参考](https://learn.microsoft.com/graph/permissions-reference) 中 Mail / IMAP 委托权限的"备注"列是否出现第三方应用限制
2. 查 [Outlook 开发者博客](https://devblogs.microsoft.com/outlook-dev-blog/) 近 12 个月公告
3. 开一个免费的 Entra 支持工单，直接问："我们是一个纯本地 iOS/macOS 邮件客户端，用 IMAP.AccessAsUser.All 访问个人 MSA 邮箱，当前有无额外的验证/审核要求？"
4. 结论写回本文件末尾"核实记录"一节（日期 + 来源 + 结论）

**若结论是"IMAP 通道对第三方收紧"**：Outlook 单独走 Microsoft Graph 适配器（`Mail.ReadBasic.All`/`Mail.Read`/`Mail.Send`），架构端口已预留，与 02 文档的 Gmail-REST 备选路线同理。

## 完成标志（DoD）

- [ ] 测试 MSA 账号走通 XOAUTH2 收发（当天）
- [ ] consent 屏截图留档（决定是否做 Phase 2）
- [ ] 政策核实记录有日期、有来源、有结论
- [ ] （若做）consent 屏出现蓝色已验证徽章

## 常见坑

- 受众选成 single tenant → 个人 MSA 用户全部登录失败（endpoint 对不上），重改受众比新建还麻烦
- authority 用错：混合受众必须 `common`；`consumers` 只覆盖个人 MSA，`organizations` 只覆盖企业
- token audience：IMAP 用的 token audience 是 `https://outlook.office365.com`，Graph 用的是 `https://graph.microsoft.com` —— 两者不通用，别拿 Graph token 连 IMAP
- Graph 通道（若启用）对第三方 MSA 有显著限流（每账号每分钟级），同步引擎节流参数要按此设计

## 核实记录（随查随更）

| 日期 | 来源 | 结论 |
|---|---|---|
| 2026-11-07 | 初步搜索：未见强制 identity verification 的公开公告；见第三方客户端限流/迁移 Graph 的第三方支持文档信号 | 待工单确认 |

## 参考

- [Microsoft 标识平台概述](https://learn.microsoft.com/entra/identity-platform/v2-overview)
- [Microsoft Graph 权限参考](https://learn.microsoft.com/graph/permissions-reference)
- [Outlook 开发者博客](https://devblogs.microsoft.com/outlook-dev-blog/)
