# Mailo

纯本地（零后端）智能邮件客户端。核心理念来自 hey.com 的邮件归类管理，适配任意邮件服务商。

**一句话定位**：无云、零数据出设备的 hey 式邮件客户端；SwiftUI + Swift 6，仅 iOS + macOS（方案基线 v3）。

## 核心特性路线

- **派生视图归类**：Imbox / Feed / Paper Trail / Screener 分层是本地派生标注，不移动、不破坏服务端任何文件夹与标签
- **智能分类管线**：用户规则 > 预置名单库 > Apple Foundation Models > embedding 原型向量兜底 > Screener 待定
- **邮箱即同步通道**：多端元数据同步通过用户邮箱内的 `Mailo/Sync` 约定文件夹（append-only JSON + CRDT），不依赖任何自建服务器
- **严格 TDD**：specs 用例库（业务视角、ID 双向追溯）→ 失败测试 → 实现

## 文档地图

| 路径 | 内容 |
|---|---|
| [docs/plan/architecture-baseline.md](docs/plan/architecture-baseline.md) | **方案基线 v3**：全部架构决策、分类管线、同步设计、TDD 规范、路线图、风险清单 |
| [docs/design/design-system.md](docs/design/design-system.md) | **设计规范 v1 · Blue Box Classic**：色板 token / 排版 / 布局 / 组件 / 动效 / UX 约定（mockup 在 docs/design/mockups/） |
| [docs/launch/00-overview.md](docs/launch/00-overview.md) | 上架前置四条线的并行时间线与依赖 |
| [docs/launch/01-apple-developer-program.md](docs/launch/01-apple-developer-program.md) | Apple 开发者账号（组织主体）注册手册 |
| [docs/launch/02-google-oauth-casa.md](docs/launch/02-google-oauth-casa.md) | Gmail OAuth 验证 + CASA Tier 2 自扫手册 |
| [docs/launch/03-microsoft-entra-outlook.md](docs/launch/03-microsoft-entra-outlook.md) | Microsoft Entra 应用注册 + 政策核实手册 |
| [docs/launch/04-privacy-policy-github-pages.md](docs/launch/04-privacy-policy-github-pages.md) | 隐私政策模板与部署 |

## 状态

- **v0.1 已交付（2026-11-07）**：6 个 SwiftPM 包 + 双端 App 骨架，42 条用例，CI 8 项必需检查全绿
- 完成度与用户侧待办总账：[docs/DELIVERY.md](docs/DELIVERY.md)
- 方案：基线 v3 · 设计规范 v1（Blue Box Classic）
- 开发入口：[AGENTS.md](AGENTS.md)（TDD 流程与常用命令）

> 仓库已公开（2026-11-07）。上架运营文档保留在 `docs/launch/`（含主体名与费用量级，均为非密级信息）；
> 密钥与证书永不入库（见 .gitignore 与 AGENTS.md 约定）。
