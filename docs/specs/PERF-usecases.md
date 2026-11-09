# PERF · 性能门禁用例

## PERF-001 镜像层批量导入吞吐
- **Given** 1,000 封邮件事件（真实规模的 1%，CI 稳定阈值）
- **When** 逐封 upsert（含 FTS 触发器）
- **Then** 总耗时 < 10s（约 ≥100 封/秒；生产 10 万封级导入以批量事务优化，见 DELIVERY）
- **Status**: draft
- **Tests**: `perf_001_bulk_upsert_throughput`

## PERF-002 IMAP 解析吞吐
- **Given** 5,000 行 FETCH 响应字节（含 ENVELOPE）
- **When** 解析
- **Then** 总耗时 < 5s（高水位同步的毫秒级单批远低于此，门禁防退化为 O(n²)）
- **Status**: draft
- **Tests**: `perf_002_parse_throughput`

## PERF-003 列表同步不请求正文
- **Given** headerFirst 引擎
- **When** 观察 FETCH wire 命令
- **Then** items 不含 BODY[]（列表同步传输量从 O(全文) 降到 O(信封)）
- **Status**: draft
- **Tests**: `sync_013_header_first_fetch`（同源断言）

## PERF-004 列表日期零重复解析（v2：增量复用）
- **Given** 列表加载 200 行（date 为 RFC2822 字符串），随后发生 flags-only 或新增/改日期更新
- **When** 行渲染取时间标签与日期分组
- **Then** 每行渲染路径零 DateFormatter 分配；索引按 stableId/raw 增量复用，flags-only 零解析；day/time 标签在索引构建时一次计算，滚动期间无 Calendar/解析开销
- **Status**: green
- **Tests**: `perf_004_row_date_no_formatter`, `perf_005_flags_only_reuses_date_index`

## PERF-005 选择响应与冗余渲染抑制（v1）
- **Given** 已加载 HTML 邮件、200 行独立日期列表、可阻塞的假传输
- **When** 选择邮件、标已读、接收无关模型更新或快速连续切换
- **Then** 相同 HTML/policy 触发 0 次额外 WebView load，HTML/policy 变化各 1 次；flags-only 更新 0 次日期解析且成员/顺序不变；只有最新选择可提交正文
- **And** 网络、MIME 解析不在 MainActor 上同步等待；runner 仍保持 MAIL-025 的命令序列化
- **Status**: green
- **Tests**: `perf_005_webview_reload_guard`, `perf_005_flags_only_reuses_date_index`, `perf_005_latest_selection_wins`, `perf_005_detail_parse_off_main`

**Status**: green
- **Tests**: `perf_006_pacing_and_window`

**Status**: green
- **Tests**: `perf_007_line_reader_throughput`
