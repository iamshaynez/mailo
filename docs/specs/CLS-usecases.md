# CLS · 分类管线用例

> 归属：`packages/CoreKit/Sources/CoreKit/Classification`
> 管线结构（基线 v3 §5）：① 用户规则 > ② 预置名单库 > ③ 模型 > ④ Screener 待定；
> 结果冻结幂等；纠正生成显式规则。

## CLS-001 用户规则永远赢
- **Given** 规则集含 `senderExact("boss@corp.com") → feed`，名单库含 `corp.com → paperTrail`
- **When** 来自 `boss@corp.com` 的邮件进入管线
- **Then** 判定为 `feed`，reason 为 `.userRule`，不查询名单库
- **Status**: green
- **Tests**: `cls_001_user_rule_wins_over_roster`

## CLS-002 名单库域名命中
- **Given** 名单库含 `netflix.com → feed`，规则集为空
- **When** 来自 `no-reply@NETFLIX.com`（大小写不一致）的邮件进入管线
- **Then** 判定为 `feed`，reason 为 `.roster`（匹配键规范化为小写）
- **Status**: green
- **Tests**: `cls_002_roster_domain_match_case_insensitive`

## CLS-003 规则与名单库均未命中 → 交给模型
- **Given** 规则集、名单库均无该发件人/域名的条目
- **When** 邮件进入管线
- **Then** 管线返回 `needsModel`（模型调用发生在管线外，由调用方经 MlEngine 端口执行后回填）
- **Status**: green
- **Tests**: `cls_003_unmatched_goes_to_model`

## CLS-004 模型低置信 → Screener 待定
- **Given** 管线返回 `needsModel`，模型建议 `feed`，置信度 0.42，阈值 0.60
- **When** 应用模型结果
- **Then** 最终判定为 `screener`（宁可待定，不可错分），reason 记录置信度
- **Status**: green
- **Tests**: `cls_004_low_confidence_goes_to_screener`

## CLS-005 分类结果冻结（幂等）
- **Given** 邮件 `m1` 已冻结为 `imbox`
- **When** 同一邮件（同稳定主键）再次进入管线，且此时存在一条本会把它分进 `feed` 的用户规则
- **Then** 仍返回 `imbox`，reason 为 `.frozen`，不触发任何重推
- **Status**: green
- **Tests**: `cls_005_frozen_result_never_reclassified`

## CLS-006 手动纠正生成显式规则
- **Given** 用户把来自 `news@indietable.co` 的邮件从 Screener 手动归入 `feed`
- **When** 调用 `UserRule.correction(sender:bucket:at:)` 生成规则并装入管线
- **Then** 下封来自 `news@indietable.co` 的邮件直接命中 `.userRule` 判定为 `feed`
- **Status**: green
- **Tests**: `cls_006_correction_becomes_explicit_rule`

## CLS-007 规则匹配优先级：sender > domain > subject
- **Given** 三条规则同时可能命中：`senderExact`、`domainExact`、`subjectContains`
- **When** 一封三者全中的邮件进入管线
- **Then** 按 sender → domain → subject 顺序取第一个命中
- **Status**: green
- **Tests**: `cls_007_matcher_precedence`

## CLS-008 一端推理、全端共享（管线视角）
- **Given** 设备 B 经同步通道收到 `m1 → imbox` 的分类条目并入冻结表
- **When** `m1` 到达设备 B 的管线
- **Then** 直接返回 `.frozen` 判定，不再进入模型路径
- **Status**: green
- **Tests**: `cls_008_synced_result_skips_model`

## CLS-009 预置名单库种子与热更覆盖
- **Given** 内置种子（v1：高置信无歧义域名）与 CDN 热更覆盖表
- **When** 组装 Roster 后对种子域名分类
- **Then** 种子命中正确桶（订阅/通知→feed、收据/账单→paperTrail）；覆盖表优先于种子；银行等歧义域名**不在种子**（宁缺勿滥，交 Screener）
- **Status**: draft
- **Tests**: `cls_009_roster_seed_and_overrides`

## CLS-010 Screener 决策流（批准即规则）
- **Given** 未知发件人邮件 X 处于 Screener 待定（冻结为 screener 桶）
- **When** 用户决定 decideScreener(X, to: .feed)
- **Then** 生成该发件人的显式规则（senderExact→feed）并入管线；X 的桶更新为 feed；**下一封同发件人邮件直接命中规则进 feed**（不再待定）；Block 分支语义 v2 移交 CLS-011（blocked 桶 + 显式规则），不再保持 .screener
- **Status**: draft
- **Tests**: `cls_010_screener_decision_flow`

## CLS-011 Block 桶语义（Screener 的第四键）
- **Given** 未知发件人邮件 X 处于 Screener 待定，用户决定 Block
- **When** decideScreener(X, to: .blocked)
- **Then** 生成 senderExact→blocked 显式规则（同 CLS-010 批准语义）；X 冻结为 blocked 桶；blocked 邮件不出现在任何导航桶（含 Screener 计数递减）；下一封同发件人邮件直接命中规则进 blocked（永不再打扰）
- **Status**: draft
- **Tests**: `cls_011_block_bucket_semantics`
