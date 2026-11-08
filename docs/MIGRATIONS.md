# 数据库迁移登记表（项目标准）

> **标准（STORE-009）**：schema 与代码版本绑定。每版本一个迁移，`MirrorStore` 初始化自动执行；
> **已合入的迁移永不修改，只允许新增**；新迁移必须同步登记于此与 `MirrorStore.releasedMigrations`，
> 契约测试 `store_009_migration_contract` 锁定两者一致。历史教训：改已发布迁移对存量库无效（STORE-008）。

| 迁移 | 内容 | 登记日期 |
|---|---|---|
| v1 | mail / classification 表 + FTS5（trigram + 触发器） | 2026-11-07 |
| v2-sync-state | 存量库补 sync_state（快照持久化，SYNC-015） | 2026-11-08 |
| v3-meta | meta 表（schema/app 版本绑定与诊断） | 2026-11-08 |

## 新增迁移 checklist
1. `makeMigrator()` 注册 `vN-短描述`（N = 上一版本 +1）
2. `releasedMigrations` 追加
3. 本表追加一行（内容 + 日期）
4. 涉及行为变化 → specs 登记用例
