# 上架前置事务总览（M0 第一天并行启动）

> 这 4 条线都是**非技术开发**，但都有外部等待周期（几天到数周）。
> 它们不在关键路径上开发代码，但在关键路径上**决定你何时能公开上架**。
> 原则：第一天全部点火，用"等待窗口"写代码。

## 文档索引

| 编号 | 文档 | 首个动作耗时 | 外部等待周期 | 费用量级 |
|---|---|---|---|---|
| 01 | [Apple Developer Program](01-apple-developer-program.md) | 1 小时 | D-U-N-S 最长 2 周 + 核实约 5 个工作日 | $99/年 |
| 02 | [Google OAuth 验证 + CASA](02-google-oauth-casa.md) | 半天（测试模式当天可用） | 验证 4-6 周 + CASA 扫描数周 | $500-4500/年 |
| 03 | [Microsoft Entra / Outlook 接入](03-microsoft-entra-outlook.md) | 半天（应用注册当天可用） | publisher 验证数周（可选/待核实） | $0 起步 |
| 04 | [隐私政策 + GitHub Pages](04-privacy-policy-github-pages.md) | 2 小时 | 无（但被 02 依赖） | $0 |

## 依赖关系

```
01 Apple 账号 ──┬──> CI 证书 / TestFlight / App Store 记录
                └──> bundle id 定死 ──> 02 的 iOS OAuth client、03 的 MSAL redirect URI

04 隐私政策 URL ──> 02 Google 验证提交时必填
                └──> App Store Connect / 02 / 03 三处引用同一个 URL
```

**推论：第一周必须完成的三件事——(a) 定 bundle id，(b) 定主体（个人/公司），(c) 隐私政策 URL 上线。** 其余都可以在等待窗口里推进。

## 并行时间线（示意）

```
第 1 周   ██████████ 01 注册+DUNS申请 / 02 建项目+测试模式 / 03 应用注册 / 04 上线
第 2-3 周 ....等待..... 01 DUNS+核实 / 开发 M0/M1
第 4 周   ██████     01 激活 → CI 证书、TestFlight；02/03 内测打通
第 5-10 周 ....开发..... M1/M2；02 等验证窗口成熟（内测期用测试模式）
M2 起     ██████████ 02 提交正式验证 + CASA；03 视核实结果决定 publisher 验证
M3       上架提交：Apple 审核 + 02/03 验证完成
```

## 每日核查清单（放在日历/看板）

- [ ] 01：D-U-N-S 是否已签发（超 2 周未出 → 打 D&B 跟进电话）
- [ ] 02：Google 是否发来 assessment 邮件（验证提交后）
- [ ] 03：政策核实结论（见 03 文档末尾的"待核实"项）
- [ ] 续费/复审日历：Apple 年费、CASA 年审（12 个月有效）
