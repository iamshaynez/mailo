# 01 · Apple Developer Program 注册（中国大陆公司主体）

> 目的：App Store 上架、TestFlight 内测、证书/CI 打包入口。
> 中国大陆公司注册组织账号**完全可行**（大量中国公司先例），流程与海外一致，
> 差异在：人民币付款、中文电话核实、以及一个**必须显式决策的上架地区问题**（见 §3）。
> 信息查证时间：2026-11，以 Apple 官方帮助页为准。

## 0. 前置决策（注册前必须定死）

1. **主体**：用大陆公司实体注册（**不要用个人账号**——上架显示个人姓名，且公司主体迁移 app 很折腾）
2. **Bundle id 定死**（如 `com.<公司域名>.mailo`），Google/Microsoft 注册复用，改起来极痛
3. **上架地区决策**（见 §3，影响是否需要 ICP/App 备案）——建议在注册同周定下来

## 1. 申请 D-U-N-S 编号（免费，最长等待项 ~2 周）

1. 打开 [Apple 的 D-U-N-S 查询页](https://developer.apple.com/D-U-N-S/)
2. 用公司**英文名**查重（大陆公司注册、开户时可能已生成，先查再申请）
3. 查无 → 同页提交申请：法定实体名（英文，与邓白氏记录一致）、总部地址、电话、联系人
4. D&B（邓白氏）在中国有业务，跟进电话可能是中文，如实回答可加速

**坑**：实体名/地址与 D&B 记录**逐字一致**（标点、缩写、大小写、拼音拼法）是 Apple 核实通过的关键；信息有误先在 D&B 侧更正（再等 1-2 周）。

## 2. 组织注册

1. 注册**公司专属**管理 Apple ID（如 `apple-dev@公司域名`），开启双重认证 —— Account Holder 应由有权签字人持有
2. https://developer.apple.com/programs/enroll/ → 用该 Apple ID → 选 **Company / Organization**
3. 填写：法定实体名（同 D&B）、D-U-N-S、总部地址电话、公司网站、**法务联系人（Legal Contact）**
4. 同意协议，付款 **$99/年（大陆可付人民币，约 ¥688）**
5. Apple 电话核实（几天内，中文）：打给法务联系人确认"是否授权该公司注册" —— 提前打招呼，别漏接

## 3. ⚠️ 上架地区决策：默认**不勾选中国大陆区**

这是大陆主体最重要的一个显式决策：

| 选项 | 后果 |
|---|---|
| **不上中国区**（默认建议） | 无任何备案义务；大陆 iPhone 用户无法在国区搜到（切外区账号可装，属用户自发行为）；与"海外为主"的市场定位一致 |
| 上中国区 | 2023 年起 App Store 中国区**硬性要求 ICP 备案（App 备案）号**：需先完成公司网站备案（要一台大陆服务器 + 域名接入），周期 2-6 周，与零后端理念冲突且引入持续合规义务 |

**建议**：首发全球区 - 中国大陆；大陆市场若将来认真做，届时经云服务商（阿里云/腾讯云）补备案流程。

**边界澄清（2026-11 确认）**：
- 备案义务只由"上架中国区 App Store"触发，与账号主体是大陆公司、Apple ID 注册地区**无关**；大陆主体 + 不勾选中国大陆发布地区 = 无备案义务
- **TestFlight 内测不要求备案号**：大陆测试者可正常经 TestFlight 安装（国区不上架后，大陆 iOS 用户的正规试用通道）
- Mac App Store 同规则

## 4. 激活后立即做的 5 件事（工程侧联动）

1. 记录 **Team ID**（CI 配置用）
2. Identifiers → 注册 App ID → 首版无特殊 entitlement（不做默认邮件客户端，避开 Mail entitlement 审核）
3. 生成 **Apple Development** + **Apple Distribution** 证书，私钥进公司保险库
4. App Store Connect：创建 App 记录，**发布地区勾选时执行 §3 决策**；App Privacy 填 "Data Not Collected"（按 04 文档）
5. 日历记：**年费续费日**（¥688）、Account Holder 变更流程

## 完成标志（DoD）

- [ ] Membership Active，App Store Connect 能建 App 记录，发布地区已按 §3 配置
- [ ] CI 能打出 distribution 签名包（TestFlight 可装）
- [ ] Team ID / 证书 / bundle id 位置记录进 `docs/launch/secrets-location.md`（只记位置不记密钥）

## 卡住时的降级路径

- D-U-N-S 卡 3 周以上 → 用 Apple D-U-N-S 帮助页的 D&B "Call Me" 跟进入口
- 组织核实反复失败 → 可先用**个人 Apple 账号**做 M0/M1 真机调试（功能等价）；上架前必须回到组织账号

## 参考

- [Apple: D-U-N-S Number 帮助](https://developer.apple.com/help/account/membership/D-U-N-S)
- [Apple: Program Enrollment 帮助](https://developer.apple.com/help/account/membership/program-enrollment)
- 工信部 App 备案要求（2023）：如需上中国区，经云服务商（阿里云/腾讯云）提交，流程见其备案控制台
