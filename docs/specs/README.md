# Mailo 用例库规范（specs）

> 本目录是**业务视角测试用例的单一事实来源**。所有功能先在此登记用例，
> 再写失败测试（测试名引用用例 ID），再实现，最后把用例状态翻绿。
> 对应架构基线 v3 §8（D11 严格 TDD）。

## 能力域编号

| 前缀 | 域 | 归属包 |
|---|---|---|
| `CLS` | 分类管线（规则/名单库/模型/冻结/纠正） | packages/CoreKit · Classification |
| `SYNC` | `Mailo/Sync` 条目与 CRDT 合并 | packages/CoreKit · Sync |
| `MAIL` | 协议域（稳定主键、MIME 解析、IMAP 能力协商） | packages/CoreKit · Mail / MailProtoKit |
| `STORE` | 本地镜像（GRDB/FTS5/migration 契约） | packages/MirrorKit |
| `ML` | 模型网关与原型向量 | packages/MlKit |
| `OAUTH` | OAuth 常量与凭证保管 | packages/AuthKit |
| `PERF` | 性能门禁（列表滚动、大邮箱导入） | 各处 |
| `DESIGN` | 设计系统 token/多语言/动效（规范的可测面） | packages/DesignKit |
| `JOURNEY` | E2E 用户旅程与装配 | packages/DesignKit（装配层；apps/ XCUITest 为后续补充） |

## 用例文件格式

每个能力域一个文件 `XXX-usecases.md`，表驱动：

```markdown
## CLS-001 <一句话行为标题>
- **Given** <前置状态>
- **When** <触发动作>
- **Then** <可观察结果>
- **Status**: green   ← draft / red / green
- **Tests**: `ClassificationPipelineTests/cls_001_...`
```

## 状态与流程（严格 TDD）

```
draft（写用例）→ red（写测试并确认失败，占位实现）→ green（实现通过）→ 合入
```

- 测试命名：`<用例ID小写>_<行为短名>`，Swift Testing 里 `@Test("CLS-001 ...")`
- **一条用例至少一个测试引用；一个测试必须引用一条用例**（双向可追溯，CI 校验脚本后续补）
- 用例变更（改行为）= 改 Given/When/Then + 版本号 +1，禁止静默改语义
- 实现不许为通过测试而在用例之外发明行为

## 用例索引（105 条；green 58 / draft 47，2026-11-08 Slate Concept v2.1）

- [CLS-usecases.md](CLS-usecases.md)：分类管线 11 条（含 CLS-011 Block 桶）
- [SYNC-usecases.md](SYNC-usecases.md)：CRDT 合并与同步 17 条
- [MAIL-usecases.md](MAIL-usecases.md)：协议域 26 条（含 MAIL-026 UID STORE）
- [STORE-usecases.md](STORE-usecases.md)：镜像与 migration 契约 10 条
- [ML-usecases.md](ML-usecases.md)：模型网关 5 条
- [OAUTH-usecases.md](OAUTH-usecases.md)：OAuth 4 条
- [PERF-usecases.md](PERF-usecases.md)：性能门禁 5 条
- [JOURNEY-usecases.md](JOURNEY-usecases.md)：旅程/装配 + DESIGN 设计系统 27 条（Slate Concept v2.1 连续表面/控件/动效已覆盖）
