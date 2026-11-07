# AGENTS.md — 仓库地图与开发约定

> 给 AI Agent（与人类）的单一入口。先读基线再动代码。

## 必读

1. `docs/plan/architecture-baseline.md` — 全部决策（D1-D14），改决策先改基线
2. `docs/specs/README.md` — 用例库规范（TDD 流程的唯一权威）
3. `docs/design/design-system.md` — UI token（做 apps/ 时）

## 仓库结构

```
packages/CoreKit        # 纯 Swift 域核心（零 UI/IO 依赖）——测试主战场
  Sources/CoreKit/
    Classification/     # 分类管线（CLS-*）
    Sync/               # Mailo/Sync 条目与 CRDT 合并（SYNC-*）
    Mail/               # 稳定主键等协议域（MAIL-*）
  Tests/CoreKitTests/
docs/specs/             # 业务用例库（单一事实来源；测试必须引用用例 ID）
docs/{plan,launch,design}/
```

规划中（勿提前创建）：`packages/MailProtoKit`（IMAP + 假服务器）、`packages/SyncKit`、
`packages/MlKit`、`apps/MailoIOS`、`apps/MailoMac`（XcodeGen 生成，禁手改 pbxproj）。

## 开发铁律（严格 TDD，D11）

1. **先在 `docs/specs/` 登记用例**（Given/When/Then + ID），状态 draft
2. **再写测试**：命名 `<用例ID小写>_<行为短名>`，如 `cls_004_low_confidence_goes_to_screener`；
   占位实现让测试编译通过并**确认红灯**
3. **再实现**，测试全绿后把用例 Status 翻 green
4. 一条用例 ≥ 一个测试引用；禁止无用例ID 的行为测试；禁止为过测试发明用例外行为

## 常用命令

```bash
swift test --package-path packages/CoreKit     # 全部测试
# CI 同款；本地需完整 Xcode 或健康 CLT（见 docs/plan 基线 M0 备注）
```

## 约定

- Swift 值类型优先；域核心零 IO（端口协议注入）；Sendable 全覆盖
- 公共 API 都要 doc comment，注明对应用例 ID 或基线章节
- 提交信息格式：`<scope>: <做了什么>`（scope ∈ core/spec/docs/ci/launch…）
- 本仓库已公开：**密钥、凭证、证书、真实服务器会话数据永不入库**；契约测试 cassette 必须脱敏
