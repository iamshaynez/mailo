# SYNC · `Mailo/Sync` 条目与 CRDT 合并用例

> 归属：`packages/CoreKit/Sources/CoreKit/Sync`
> 载体：用户邮箱约定文件夹内的 append-only JSON 条目；合并语义见基线 v3 §6。

## SYNC-001 append-only 条目合并为确定序
- **Given** 设备 A、B 各自产生的任意交错条目序列（同一封 JSON 邮件内乱序到达）
- **When** 对同一集合做合并（无论接收顺序如何）
- **Then** 合并结果一致（顺序无关、结果确定）
- **Status**: green
- **Tests**: `sync_001_merge_is_order_independent`

## SYNC-002 分类条目 first-writer-wins
- **Given** 设备 A 以 ts=1000 写入 `m1 → feed`，设备 B 以 ts=1200 写入 `m1 → imbox`
- **When** 合并两组条目
- **Then** `m1` 为 `feed`（时间戳小者/先写者胜）；ts 相等时按 deviceId 字典序小者胜（tiebreak 确定）
- **Status**: green
- **Tests**: `sync_002_classification_first_writer_wins`

## SYNC-003 规则条目 LWW
- **Given** 同一发件人键，设备 A ts=1000 写 `→ feed`，设备 B ts=1200 写 `→ screener`
- **When** 合并
- **Then** 生效规则为 ts=1200 的 `→ screener`（后写覆盖）
- **Status**: green
- **Tests**: `sync_003_rule_lww`

## SYNC-004 tombstone 阻止旧写复活
- **Given** 规则键 `k` 存在 tombstone(ts=1000)
- **When** 合并一条 ts=500 的同键 `ruleUpsert`（离线设备的迟到写入）
- **Then** `k` 保持删除状态（按 ts 比较，500 < 1000 不生效）
- **Status**: green
- **Tests**: `sync_004_tombstone_blocks_stale_upsert`

## SYNC-005 快照压缩等价（draft）
- **Given** 历史条目被压缩为快照条目 + 增量条目
- **When** 与"全量原始条目"分别合并
- **Then** 两者的最终状态等价
- **Status**: draft（v2 实现，防文件夹无限膨胀）
- **Tests**: —

## SYNC-006 首次全量同步
- **Given** 假服务器 INBOX 有 3 封邮件，引擎无快照
- **When** `sync(folder: "INBOX", snapshot: nil)`
- **Then** 产出 3 个 MailEvent（含稳定主键/原始字节/主题/发件人），返回新快照（uidValidity + 最高 UID）
- **Status**: draft
- **Tests**: `sync_006_initial_full_sync`

## SYNC-007 增量同步（UID 高水位）
- **Given** 引擎已有快照（最高 UID=3），服务器此后新增第 4 封
- **When** 再次 `sync`
- **Then** 只产出 1 个 MailEvent（uid=4）；前 3 封不重发
- **Status**: draft
- **Tests**: `sync_007_incremental_highwater`

## SYNC-008 UIDVALIDITY 重置：重拉全量但分类不丢
- **Given** 引擎已有快照（uidValidity=7），服务器重建 INBOX（uidValidity=99，UID 全变但邮件原文相同）
- **When** 再次 `sync`
- **Then** 产出 `.resetDetected(old:7, new:99)` 且携带重拉的全量事件；**重拉事件中每封邮件的稳定主键与重置前相同**（分类标注按主键存活）
- **Status**: draft
- **Tests**: `sync_008_uidvalidity_reset_keeps_stable_ids`

## SYNC-009 写节流（30s / 20 条）
- **Given** 本地产生条目的队列
- **When** 入队第 19 条 / 第 20 条；或 1 条入队 31 秒后定时器触发
- **Then** 19 条不 flush；满 20 条立即 flush；超时路径同样 flush（避免高频 APPEND 触碰服务器限额）
- **Status**: draft
- **Tests**: `sync_009_flush_throttle`

## SYNC-010 wire 编解码往返
- **Given** 一组条目
- **When** `SyncCodec.encode` 为一封 MIME 邮件字节（JSON lines body）再 `decode`
- **Then** 条目集合往返相等；邮件头带 Message-ID（可被 IMAP 文件夹正常收纳与去重）
- **Status**: draft
- **Tests**: `sync_010_codec_roundtrip`

## SYNC-011 轮询编排策略（成功复位/失败退避）
- **Given** PollingPolicy（基准 30s，封顶 300s）
- **When** 连续成功；连续失败
- **Then** 成功后回到基准间隔；失败后指数翻倍封顶 300s；恢复成功立即复位
- **Status**: draft
- **Tests**: `sync_011_polling_policy_backoff`

## SYNC-012 首轮同步最近窗口（大邮箱保护）
- **Given** 邮箱 1000 封（UID 1..1000），引擎无快照，initialWindow=50
- **When** 首次 sync
- **Then** FETCH 区间锚定 UIDNEXT 只拉最近 50 封（NOT 1:* 全量；基线 §5 回填策略"最近优先"）；增量轮次不受影响
- **Status**: draft
- **Tests**: `sync_012_initial_recent_window`

## SYNC-013 两段式同步（列表 ENVELOPE-only）
- **Given** 同一邮箱（含 200 封），引擎 headerFirst 模式 vs 旧全量模式
- **When** 首轮列表同步
- **Then** FETCH items 为 `(UID FLAGS ENVELOPE)`（**无 BODY[]**）；事件带 subject/from（ENVELOPE 提取）而 raw 为空（正文按需）；同步耗时显著下降（PERF-003 联动）
- **Status**: draft
- **Tests**: `sync_013_header_first_fetch`

## SYNC-014 正文按需拉取（lazy body）
- **Given** 一封已入库但 raw 为空的邮件（仅 ENVELOPE）
- **When** `engine.fetchBody(uid:transport:)` 单封 `FETCH (UID BODY.PEEK[])`（PEEK 不置已读）
- **Then** 返回该邮件完整原文；假服务器确认 \Seen 标记未被设置
- **Status**: draft
- **Tests**: `sync_014_lazy_body_fetch`

## SYNC-015 同步快照持久化（重启只拉增量）
- **Given** 首轮同步后快照入库，App 重启（新 store 实例）后同邮箱再来一封新邮件
- **When** 第二轮同步（从库恢复快照）
- **Then** 只产生 1 个事件（增量）；FETCH 区间为高水位+1 而非全窗口
- **Status**: draft
- **Tests**: `sync_015_snapshot_persisted`

## SYNC-016 历史回填（任意区间拉取，v2：按需触发）
- **Given** 已完成最近窗口同步的邮箱（更早的邮件未拉）
- **When** 引擎 `fetchRange("N:M")`（AppModel 按需逐批调用，每批一条命令；v2：由列表滚动到底触发，不再后台自动全量）
- **Then** 返回该 UID 区间的事件（ENVELOPE 模式、事件构造与列表同步一致）；逐批向 UID 1 推进（空批=UID 空洞，继续推进不死循环）；到达 UID 1 后标记无更多历史
- **Status**: green
- **Tests**: `sync_016_backfill_range`, `sync_018_fetch_more_history`

## SYNC-017 回填进度可见（v2：按需批进度）
- **Given** 历史回填批进行中（SYNC-016 v2 按需逐批推进）
- **When** 每批完成
- **Then** 模型暴露 backfillProgress{fetched, total}（UI 呈现进度行）；批完成后归 nil（无长驻后台任务）；轮询/前台不受进度影响
- **Status**: green
- **Tests**: `sync_017_backfill_progress`

**Status**: green
- **Tests**: `sync_018_fetch_more_history`, `sync_018_no_more_when_oldest_is_one`
