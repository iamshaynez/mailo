# ML · 本地模型域用例（MlKit）

> 归属：`packages/MlKit`。MlEngine 端口 + Mock + embedding 原型向量引擎（基线 §5 ③④）+ golden 评测工具。
> 真实模型（Foundation Models / Core ML）实现挂在 app 层同一端口，本包只做可确定测试的纯逻辑。

## ML-001 原型投票：最近桶胜
- **Given** imbox/feed 各有 1 个原型向量，新邮件 embedding 与 feed 原型余弦更高
- **When** `PrototypeEngine.classify`
- **Then** 判定 feed
- **Status**: draft
- **Tests**: `ml_001_nearest_prototype_wins`

## ML-002 置信度 = 区分度（低区分度 → 低置信）
- **Given** 新向量与两个桶的原型余弦几乎相同 vs 一边倒
- **When** classify
- **Then** 一边倒时高置信（≥0.8）；近平票时低置信（<0.6，管线将判 Screener）
- **Status**: draft
- **Tests**: `ml_002_confidence_separation`

## ML-003 原型自学习（纠正即时生效）
- **Given** 某发件人域向量更靠近 imbox 原型，用户纠正为 feed
- **When** `update(bucket: .feed, embedding:)` 后同域邮件再来
- **Then** 判定 feed（滚动更新使纠正即时反映，CLS-006 的模型侧配合）
- **Status**: draft
- **Tests**: `ml_003_prototype_self_learning`

## ML-004 Mock 网关确定性
- **Given** 同一输入两次调用 MockGateway
- **When** 取输出
- **Then** 完全一致（golden 评测与 CI 回归的前提）
- **Status**: draft
- **Tests**: `ml_004_mock_gateway_deterministic`

## ML-005 golden 评测与 JSONL 往返
- **Given** 若干标注样本（input + 期望桶）序列化为 JSONL 再读回
- **When** 用 Mock 网关评估
- **Then** 往返无丢失；准确率/分桶计数正确（发版门禁的计算内核）
- **Status**: draft
- **Tests**: `ml_005_golden_report_and_jsonl`
