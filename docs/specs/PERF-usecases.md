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
