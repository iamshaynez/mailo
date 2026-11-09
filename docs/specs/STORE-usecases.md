# STORE · 本地镜像层用例（MirrorKit · GRDB+FTS5）

> 归属：`packages/MirrorKit`。UI 唯一数据源（基线 v3 §3 本地镜像层）。
> 表：mail（stableID 主键）+ classification（冻结态）+ FTS5 虚表（trigram，中文子串可搜）。

## STORE-001 邮件事件 upsert 幂等
- **Given** 同一 stableID 的邮件事件先以 uid=5 入库，再以 uid=5 重复入库（flags 变化）
- **When** 两次 upsert
- **Then** 表中仍只有一行，flags 为新值，无重复
- **Status**: draft
- **Tests**: `store_001_upsert_idempotent`

## STORE-002 bucket 查询按日期倒序
- **Given** 三封邮件分属 imbox/feed/imbox，日期交错
- **When** 查询 bucket=imbox
- **Then** 仅返回两封 imbox，按日期倒序
- **Status**: draft
- **Tests**: `store_002_bucket_query_ordered`

## STORE-003 FTS 中文子串搜索（trigram）
- **Given** 邮件主题含"合同修订"
- **When** 搜索 "同修"（2 字子串，无分词）
- **Then** 能命中该邮件（FTS5 trigram 对中文子串有效；纯 ASCII 邮件不误命中）
- **Status**: draft
- **Tests**: `store_003_fts_chinese_substring`

## STORE-004 分类冻结持久化
- **Given** 邮件已入库，分类管线冻结其为 imbox
- **When** 写入分类后重启存储（新连接）再查询
- **Then** bucket 视图仍包含该邮件（冻结态持久，跨连接存活）
- **Status**: draft
- **Tests**: `store_004_classification_persisted`

## STORE-005 UIDVALIDITY 重置后的 uid 刷新
- **Given** stableID=X 的邮件 uid=5；服务器重置后同 stableID 以 uid=101 再入库
- **When** upsert 新事件
- **Then** 仍只有一行，uid=101（分类标注不丢——STORE-004 的主键保证）
- **Status**: draft
- **Tests**: `store_005_uid_refresh_on_reset`

## STORE-006 桶计数查询
- **Given** 多封邮件分属各桶
- **When** bucketCounts
- **Then** 每桶数量正确（侧栏徽章数据源）
- **Status**: draft
- **Tests**: `store_006_bucket_counts`

## STORE-007 批量事务 upsert
- **Given** 200 封邮件事件
- **When** upsertBatch（单事务）vs 逐封 upsert
- **Then** 数据等价；批量耗时显著低于逐封（事务开销摊平）
- **Status**: draft
- **Tests**: `store_007_batch_upsert`

## STORE-008 存量库迁移兼容（v2）
- **Given** 一个 v1 时期创建的存量库（已应用旧 v1、无 sync_state 表）
- **When** 新版本打开该库（v2 migration 补建表）
- **Then** 初始化成功、saveSnapshot/loadSnapshot 正常；邮件与分类数据保留；migration 铁律：已发布迁移永不修改，只新增
- **Status**: draft
- **Tests**: `store_008_v2_upgrade_existing_db`

## STORE-009 迁移契约锁定（项目标准）
- **Given** 本项目标准：schema 与代码版本绑定，每版本一个迁移、自动执行、已发布迁移永不修改（MIGRATIONS.md 登记表为准）
- **When** MirrorStore 初始化（新库/存量库/二次打开）
- **Then** 已应用迁移清单与登记表**完全一致**（顺序+内容）；二次打开幂等；schema 版本可查询（诊断可见）；meta 表记录 schema/app 版本
- **Status**: draft
- **Tests**: `store_009_migration_contract`

## STORE-010 本地 flags 更新（markSeen）
- **Given** 已入库邮件 X（flags 不含 \Seen）
- **When** store.setFlags(stableId:, merge: ["\\Seen"])
- **Then** flags 为并集且幂等（重复调用不重复追加）；分类行与其余字段不受影响；无 schema 迁移（UPDATE 既有列）
- **Status**: green
- **Tests**: `store_010_set_flags`

## STORE-011 本地删行（deleteMail）
- **Given** 已入库邮件 X（mail 行 + classification 行 + FTS 索引）
- **When** store.deleteMail(stableId:)
- **Then** 同一事务内 mail 行与 classification 行一并删除；FTS 由既有 AFTER DELETE 触发器自动一致（搜索不再命中）；桶计数随之消减；幂等（重复删除/不存在静默无操作）；无 schema 迁移
- **Status**: green
- **Tests**: `store_011_delete_mail`

## STORE-012 回填水位查询（最早已知 uid）
- **Given** 已入库若干邮件（uid 集合任意，含空洞）
- **When** store.oldestUid(folder:)
- **Then** 返回该文件夹最早已知 uid（min(uid)，水位即其下沿）；空库返回 nil；无 schema 迁移
- **Status**: green
- **Tests**: `store_012_oldest_uid`
