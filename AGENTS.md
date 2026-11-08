# AGENTS.md — 仓库地图与开发约定

> 给 AI Agent（与人类）的单一入口。先读基线再动代码。

## 必读

1. `docs/plan/architecture-baseline.md` — 全部决策（D1-D14），改决策先改基线
2. `docs/specs/README.md` — 用例库规范（TDD 流程的唯一权威）
3. `docs/design/design-system.md` — UI token（做 apps/ 时）

## 仓库结构

```
packages/
  CoreKit/        # 纯 Swift 域核心：分类管线/CRDT/稳定主键/MIME/账户（CLS/SYNC/MAIL）
  MailProtoKit/   # IMAP/SMTP 解析+引擎+假服务器（MAIL/SYNC/PERF）
  MirrorKit/      # GRDB+FTS5 本地镜像（STORE/PERF）
  MlKit/          # 模型网关端口+原型向量+golden（ML）
  AuthKit/        # OAuth 常量+凭证保管端口（OAUTH）
  DesignKit/      # 设计 token+三栏壳+装配模型（JOURNEY/DESIGN）
apps/
  MailoIOS/ MailoMac/   # XcodeGen 工程（禁手改 pbxproj）
docs/
  specs/          # 业务用例库（单一事实来源；测试必须引用用例 ID）
  plan/ launch/ design/ DELIVERY.md
```

CI：8 项必需检查（6 包 swift-test 矩阵 + 双端 app-build）。新包必须加入 ci.yml 矩阵
**并同步更新 branch protection 的 required contexts**（顺序错会卡死 main）。

## 开发铁律（严格 TDD，D11）

1. **先在 `docs/specs/` 登记用例**（Given/When/Then + ID），状态 draft
2. **再写测试**：命名 `<用例ID小写>_<行为短名>`，如 `cls_004_low_confidence_goes_to_screener`；
   占位实现让测试编译通过并**确认红灯**
3. **再实现**，测试全绿后把用例 Status 翻 green
4. 一条用例 ≥ 一个测试引用；禁止无用例ID 的行为测试；禁止为过测试发明用例外行为

## 分支与 PR 流程（main 受保护，2026-11-07 起）

**main 禁止直接 push（含管理员与 Agent，enforce_admins 已开启）**；
唯一进入方式：PR 合并，且 `CoreKit · swift test` CI 必须通过；合并方式仅 squash。

标准流程：

```
1. git checkout main && git pull              # 从最新 main 起步
2. git checkout -b feat/<域>-<短描述>          # 或 fix/<域>-<短描述> / docs/<短描述>
3. 开发（遵循 TDD 铁律），分支内可多个小 commit
4. git push -u origin <分支>
5. gh pr create --fill                        # PR 描述写清：动了哪些用例 ID / 决策依据
6. gh pr checks --watch                       # 等 CI 绿
7. gh pr merge --squash --delete-branch       # squash 进 main，删远端分支
8. git checkout main && git pull
```

约定：
- 分支命名：`feat/`（新功能）、`fix/`（修缺陷）、`docs/`（纯文档）、`ci/`（流水线）
- **一个 PR 一个主题**（一个 spec 域或一个 feature 目录），评审与回滚的最小单元
- PR 必须在描述中列出触及的用例 ID（如 `CLS-004, SYNC-002`）；纯文档/CI 可豁免
- 本地 main 只用来同步，不直接提交（保护规则会拒绝，别试）

## 常用命令

```bash
swift test --package-path packages/CoreKit     # 全部测试
# CI 同款；本地需完整 Xcode 或健康 CLT（见 docs/plan 基线 M0 备注）
```

## 约定

- Swift 值类型优先；域核心零 IO（端口协议注入）；Sendable 全覆盖
- **数据库 migration 一经合入永不修改，只允许新增**（改已发布迁移对存量库无效，STORE-008 教训）
- 公共 API 都要 doc comment，注明对应用例 ID 或基线章节
- 提交信息格式：`<scope>: <做了什么>`（scope ∈ core/spec/docs/ci/launch…）
- 本仓库已公开：**密钥、凭证、证书、真实服务器会话数据永不入库**；契约测试 cassette 必须脱敏
