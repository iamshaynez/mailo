# 上架前置事务总览（M0 第一天并行启动）

> 主体背景：**中国大陆公司**；iOS/macOS 走 App Store（**海外区，不含中国大陆**）。
> 平台仅 Apple 双端（基线 v3），无 Android 分发线。
> 这 4 条线都是**非技术开发**，但都有外部等待周期（几天到数周）。
> 原则：第一天全部点火，用"等待窗口"写代码。

## 文档索引

| 编号 | 文档 | 首个动作耗时 | 外部等待周期 | 费用量级 |
|---|---|---|---|---|
| 01 | [Apple Developer Program](01-apple-developer-program.md) | 1 小时 | D-U-N-S 最长 2 周 + 电话核实约 5 个工作日 | ¥688/年（人民币） |
| 02 | [Google OAuth 验证 + CASA](02-google-oauth-casa.md) | 半天（测试模式当天可用） | 验证 4-6 周 + CASA 数周 | $500-4500/年（国际卡支付） |
| 03 | [Microsoft Entra / Outlook 接入](03-microsoft-entra-outlook.md) | 半天（应用注册当天可用） | publisher 验证数周（可选/待核实） | $0 起步 |
| 04 | [隐私政策 + GitHub Pages](04-privacy-policy-github-pages.md) | 2 小时 | 无（但被 02 依赖） | $0 |

## 依赖关系

```
01 Apple 账号 ──┬──> CI 证书 / TestFlight / App Store 记录
                └──> bundle id 定死 ──> 02 的 iOS OAuth client、03 的 MSAL redirect URI

04 隐私政策 URL ──> 02 Google 验证提交时必填
                └──> App Store Connect / 02 / 03 三处引用同一 URL
```

**第一周必须完成的三件事：(a) 定 bundle id，(b) 定主体资料英文名（邓白氏/Apple/Google/Microsoft 四处一套译文），(c) 隐私政策 URL 上线。**

## 大陆主体的一页结论

- Apple：人民币付款、中文核实，流程无障碍；**发布地区不勾中国大陆**（避开 App 备案，见 01 §3；TestFlight 内测不受限）
- Google：注册/验证可用；摩擦在**国际卡付款**（提前实测）与 CASA 美元付款
- Microsoft：应用注册零门槛；Partner Center 支持中国公司
- 隐私政策站：面向海外，GitHub Pages 够用；建议绑自定义域名留迁移余地

## 并行时间线（示意）

```
第 1 周   ██████████ 01 注册+DUNS / 02 建项目+测试模式 / 03 应用注册 / 04 上线
第 2-3 周 ....等待..... 01 DUNS+核实 / 开发 M0/M1
第 4 周   ██████     01 激活 → CI 证书、TestFlight；02/03 内测打通
第 5-10 周 ....开发..... M1/M2；02 等验证窗口（内测用测试模式顶着）
M2 起     ██████████ 02 提交正式验证 + CASA；03 视核实结果决定 publisher 验证
M3       Apple 审核提交（地区按 01 §3 配置）+ 02/03 验证收尾
```

## 每日核查清单（放在日历/看板）

- [ ] 01：D-U-N-S 是否签发（超 2 周 → D&B 跟进电话）
- [ ] 02：Google 是否发来 assessment 邮件；国际卡付款是否实测通过
- [ ] 03：政策核实结论（03 文档"核实记录"表）
- [ ] 续费/复审日历：Apple 年费、CASA 年审（12 个月有效）
