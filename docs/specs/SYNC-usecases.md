# SYNC · `Mailo/Sync` 条目与 CRDT 合并用例

> 归属：`packages/CoreKit/Sources/CoreKit/Sync`
> 载体：用户邮箱约定文件夹内的 append-only JSON 条目；合并语义见基线 v3 §6。

## SYNC-001 append-only 条目合并为确定序
- **Given** 设备 A、B 各自产生的任意交错条目序列（同一封 JSON 邮件内乱序到达）
- **When** 对同一集合做合并（无论接收顺序如何）
- **Then** 合并结果一致（顺序无关、结果确定）
- **Status**: draft
- **Tests**: `sync_001_merge_is_order_independent`

## SYNC-002 分类条目 first-writer-wins
- **Given** 设备 A 以 ts=1000 写入 `m1 → feed`，设备 B 以 ts=1200 写入 `m1 → imbox`
- **When** 合并两组条目
- **Then** `m1` 为 `feed`（时间戳小者/先写者胜）；ts 相等时按 deviceId 字典序小者胜（tiebreak 确定）
- **Status**: draft
- **Tests**: `sync_002_classification_first_writer_wins`

## SYNC-003 规则条目 LWW
- **Given** 同一发件人键，设备 A ts=1000 写 `→ feed`，设备 B ts=1200 写 `→ screener`
- **When** 合并
- **Then** 生效规则为 ts=1200 的 `→ screener`（后写覆盖）
- **Status**: draft
- **Tests**: `sync_003_rule_lww`

## SYNC-004 tombstone 阻止旧写复活
- **Given** 规则键 `k` 存在 tombstone(ts=1000)
- **When** 合并一条 ts=500 的同键 `ruleUpsert`（离线设备的迟到写入）
- **Then** `k` 保持删除状态（按 ts 比较，500 < 1000 不生效）
- **Status**: draft
- **Tests**: `sync_004_tombstone_blocks_stale_upsert`

## SYNC-005 快照压缩等价（draft）
- **Given** 历史条目被压缩为快照条目 + 增量条目
- **When** 与"全量原始条目"分别合并
- **Then** 两者的最终状态等价
- **Status**: draft（v2 实现，防文件夹无限膨胀）
- **Tests**: —
