# 主体与标识记录（单一事实来源）

> 上架四线（01-04）凡引用主体名/bundle id/邮箱，一律以本文件为准。
> 决策日期：2026-11-07。

## Bundle ID

| 项 | 值 |
|---|---|
| **Bundle id（定案）** | `com.xiaowenz.mailo` |
| 决策说明 | 所有者段用 `com.xiaowenz`（个人前缀，Apple/Google/MS 均不校验域名所有权，公司主体上架无碍）；产品段 `mailo`；**上线后不可改**（App Store 记录永久绑定） |
| 引用处 | Google OAuth iOS client（02）；MSAL redirect `msauth.com.xiaowenz.mailo://auth`（03）；App Store Connect App 记录（01） |

## 公司主体

| 项 | 值 |
|---|---|
| 法定名称（中文） | 杭州望文生义科技有限公司 |
| 简称 | 望文生义 |
| 主体英文（简称） | Wangwenshengyi Technology |
| 主体英文（**D-U-N-S 建议全称**） | Hangzhou Wangwenshengyi Technology Co., Ltd. |

> ⚠️ D-U-N-S 查重时若发现公司已有记录（注册/开户时可能已生成），**英文翻译以 D&B 现有记录为准**，
> 本文件译文仅用于查无记录时的新申请。四处（邓白氏/Apple/Google/MS）必须同一套译文。

## 待办（不阻塞 M0/M1，M2 前清掉）

- [ ] **公司域名未定**。影响项与现有无域名路径：
  - Google 验证 home page → GitHub Pages 默认域名可用（04 文档）
  - App Store support URL / Google consent support email → GitHub Pages 页 + 任意可达邮箱可用
  - 04 文档"建议绑自定义域名（如 mailo.app）" → **建议尽早买个域名**（年费几十元级），越晚迁移、各平台登记的 URL 改动越麻烦
- [ ] 主体联系邮箱规范（apple-dev@ / support@）随域名定；域名未定前用现有邮箱过渡并在本文件记录
