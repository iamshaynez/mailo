# 04 · 隐私政策 + 首页（GitHub Pages 部署）

> 目的：App Store 审核硬性要求 + Google OAuth 验证硬性要求 + 02/03 consent 屏引用。
> 本线零外部等待，**2 小时上线**，但被 02 的 Phase 2 依赖，所以也在 M0 第一天完成。
> 关键原则：我们的产品事实是"零数据出设备"，隐私政策要把这件事写成**卖点**，
> 同时满足 Google 验证的特定条款要求（缺一段就会被 02 卡住）。

## Phase 1 · 写内容（直接用下面骨架，中文英文各一份）

隐私政策必须包含的段落（骨架）：

```
Mailo 隐私政策（模板）
1. 我们收集什么：不收集。
   - 邮件内容、附件、账户凭证只在你的设备上处理与存储（本地数据库，加密）
   - OAuth 令牌仅存于系统钥匙串（Keychain），永不上传
   - 应用不包含分析 SDK、广告 SDK、崩溃收集默认关闭（若日后开启需更新本政策并征得同意）
2. 数据去向：你的邮件客户端直接与你的邮件服务商通信（Gmail、Outlook、
   你自己的 IMAP 服务器）。我们没有服务器接收你的任何数据。
3. 第三方内容下载：应用会从静态 CDN 下载"预置发件人名单库"与"本地分类模型"，
   请求不含任何个人标识信息。
4. 你如何删除数据：卸载应用即删除全部本地数据。邮件本身始终在你的邮箱中。
5. Google API 服务条款（Google 验证必查段，勿删改）：
   Mailo 对 Google API 用户数据的使用遵守
   Google API Services User Data Policy（https://developers.google.com/terms/api-services-user-data-policy），
   包括 Limited Use 要求。
6. 儿童隐私 / 联系方式（运营邮箱）/ 生效日期与版本号（页脚，每次修订更新）
```

**注意**：第 5 段是 Google 验证审核的机器比对项；第 1-4 段的表述必须与 02 文档 CASA 问卷、App Store 隐私标签三处**口径完全一致**。

首页（同站 `index.html`）：一段产品介绍 + "无云·零数据出设备"定位 + 隐私政策链接 + 联系方式。Google 验证要求首页可访问且非"建设中"。

## Phase 2 · 部署到 GitHub Pages（免费 HTTPS）

1. 建公开仓库（如 `你的组织/mailo-site`），放入 `index.html` + `privacy.html`（或 `/zh/`、`/en/` 双语）
2. 仓库 Settings → Pages → Source 选 `main` 分支 / root → Save
3. 1-2 分钟后拿到 URL：`https://<org>.github.io/mailo-site/`
4. （可选，建议）绑自定义域名 `mailo.app` 之类：域名注册商加 CNAME → Pages 页填 Custom domain → 勾 Enforce HTTPS
5. 手机和桌面各打开一遍，确认 HTTPS、无 404、页脚日期正确
6. 把两个 URL 记入下表：

| 用途 | URL |
|---|---|
| 首页 | （填） |
| 隐私政策 | （填） |

## Phase 3 · 三处引用（同一 URL，改一处查三处）

1. **Google**：console.cloud.google.com → OAuth 同意屏幕 → Home page / Privacy policy 字段
2. **App Store Connect**：App 信息 → 隐私政策 URL；App Privacy 问卷选 **"未收集数据（Data Not Collected）"**（本地处理 + 无 SDK + CDN 下载无个人数据 → 成立）
3. **Microsoft**（若 03 做 publisher 验证）：consent 屏的品牌信息里引用

## 完成标志（DoD）

- [ ] 两个 URL HTTPS 可访问，被上述三处引用
- [ ] Google Limited Use 段落原文在
- [ ] 页脚版本号/日期在，仓库开了提交权限管理（政策修订要留 git 历史）
- [ ] （macOS 若走 Mac App Store）同一 URL 复用即可

## 大陆可达性说明（决策：本站面向海外，GitHub Pages 够用）

- `*.github.io` 在大陆**间歇性不可达**。我们的受众定位是海外用户 + Apple/Google 审核员（均在海外），**GitHub Pages 当前够用，不为此引入大陆服务器**
- 建议现在就绑**自定义域名**（如 `mailo.app`）：一劳永逸摆脱 `github.io` 的可达性变量，迁移时只改 DNS 不改各平台登记的 URL

## 常见坑

- 用了自定义域名却没等 HTTPS 证书生效就提交 Google 验证 → 链接报错退回
- 隐私政策与 CASA 问卷说法不一致（一边说"不收集"，一边在问卷里勾了"传输到第三方"）→ 两边都卡
- 政策更新后忘了同步 Google/App Store 的引用页面快照 → 年审时被翻旧账

## 参考

- [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy)
- [GitHub Pages 官方文档](https://docs.github.com/pages)
