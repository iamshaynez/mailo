# Mailo

纯本地（零后端）智能邮件客户端。核心理念来自 hey.com 的邮件归类管理，适配任意邮件服务商。

**一句话定位**：无云、零数据出设备的 hey 式邮件客户端；Flutter 单代码库，首发 iOS + macOS。

## 核心特性路线

- **派生视图归类**：Imbox / Feed / Paper Trail / Screener 分层是本地派生标注，不移动、不破坏服务端任何文件夹与标签
- **智能分类管线**：用户规则 > 预置名单库 > Apple Foundation Models > embedding 原型向量兜底 > Screener 待定
- **邮箱即同步通道**：多端元数据同步通过用户邮箱内的 `Mailo/Sync` 约定文件夹（append-only JSON + CRDT），不依赖任何自建服务器
- **严格 TDD**：specs 用例库（业务视角、ID 双向追溯）→ 失败测试 → 实现

## 文档地图

| 路径 | 内容 |
|---|---|
| [docs/plan/architecture-baseline.md](docs/plan/architecture-baseline.md) | **方案基线 v2**：全部架构决策、分类管线、同步设计、TDD 规范、路线图、风险清单 |
| [docs/launch/00-overview.md](docs/launch/00-overview.md) | 上架前置四条线的并行时间线与依赖 |
| [docs/launch/01-apple-developer-program.md](docs/launch/01-apple-developer-program.md) | Apple 开发者账号（组织主体）注册手册 |
| [docs/launch/02-google-oauth-casa.md](docs/launch/02-google-oauth-casa.md) | Gmail OAuth 验证 + CASA Tier 2 自扫手册 |
| [docs/launch/03-microsoft-entra-outlook.md](docs/launch/03-microsoft-entra-outlook.md) | Microsoft Entra 应用注册 + 政策核实手册 |
| [docs/launch/04-privacy-policy-github-pages.md](docs/launch/04-privacy-policy-github-pages.md) | 隐私政策模板与部署 |

## 状态

方案已收敛（2026-11-07），未开始编码。下一步见基线文档「路线图」一节的 M0。

> 本仓库为 private：包含上架流程、主体与费用规划等运营信息。
