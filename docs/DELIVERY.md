# Mailo 交付状态（v0.1 · 2026-11-07）

> 本文件是"代码侧完成度"与"用户侧待办"的总账。代码全部经 CI 验证合入 main（8 项必需检查全绿）。

## 1. 已交付（代码侧，全部在 main）

| 层 | 包 | 内容 | 用例 |
|---|---|---|---|
| 域核心 | `CoreKit` | 分类管线（冻结>规则>名单库>模型>Screener，两段式纯函数）、CRDT 合并（first-writer-wins/LWW/tombstone/快照压缩）、稳定主键（规范化+SHA256 fallback）、MIME 解析（折叠头/嵌套 multipart/BASE64/QP/GBK）、RFC2047 解码、`Mailo/Sync` wire 编解码、写节流器、账户配置与指纹 | CLS/SYNC/MAIL |
| 协议 | `MailProtoKit` | IMAP 响应解析器（括号列表/字面量跨行）、**进程内假服务器**（可配置能力/UIDVALIDITY/消息库）、同步引擎（SELECT 聚合/重置检测/高水位增量/BODY[]）、SMTP 客户端+假服务器（点填充/会话状态机） | MAIL-003~015, SYNC-006~008 |
| 存储 | `MirrorKit` | GRDB 镜像层：mail/classification 表、FTS5 trigram 外部内容表+触发器、bucket 视图、中文子串搜索（<3 字 LIKE 兜底） | STORE-001~005 |
| 模型 | `MlKit` | MlGateway 端口、确定性 Mock、原型向量引擎（余弦投票+margin 置信度+滚动自学习）、golden 评测（JSONL+分桶报告） | ML-001~005 |
| 授权 | `AuthKit` | Gmail/Outlook 配置常量（scope/host/redirect）、CredentialVault 端口（InMemory 实现，Keychain 实现挂 app 层）、token 会话刷新判定 | OAUTH-001~003 |
| UI | `DesignKit` | **UI 基准线已完成（v0.2，docs/plan/ui-baseline-audit.md）**：NavigationSplitView 三栏 + 系统 toolbar 运通蓝、List 键盘选择、命令菜单（⌘N/⌘K/⌘R/⌘⇧F/⌘⇧U/⌘S/⌘Z）、Reply/Forward/Set Aside/Block/手动纠正/undo 交互闭环、打开即已读（本地+UID STORE 写回）、Demo 隔离、正文异步加载+重试、搜索防抖、回填进度、日期索引零重复解析、token 全集+源码防漂移扫描、**多语言 en+zh-Hans（默认 en，实机验证）**、动效+减弱动态、Settings ⌘,、Compose 独立窗口（macOS）、App icon、a11y | JOURNEY-001~017, DESIGN-001~004 |
| App | `apps/MailoIOS` `apps/MailoMac` | XcodeGen 工程，CI 构建（iOS 模拟器 + macOS）通过；bundle id `com.xiaowenz.mailo` | — |
| 门禁 | CI | 8 项必需检查：6 包 swift-test × 矩阵 + 双端 app-build；main 保护（PR-only、enforce_admins、仅 squash）；PERF 吞吐门禁 | PERF-001/002 |

**用例总计**：98 条（51 green / 47 draft），见 `docs/specs/README.md` 索引。

## 2. 架构地图（一屏）

```
apps/(iOS, macOS) ── XcodeGen
  └─ DesignKit（壳+装配） ── CoreKit（纯域：分类/CRDT/主键/MIME/账户）
       ├─ MailProtoKit（IMAP/SMTP 解析+引擎+假服务器）
       ├─ MirrorKit（GRDB+FTS5 镜像）
       ├─ MlKit（网关端口+原型向量+golden）
       └─ AuthKit（OAuth 常量+凭证端口）
```

## 3. 明确未做（依赖用户侧输入或需真机，非"忘记"）

| 项 | 原因 | 接入点已备 |
|---|---|---|
| 真实邮箱联调（TcpImap/SmtpTransport 打真服务器） | 需真实邮箱账号/授权码；**传输实现已交付**（TLS/XOAUTH2/LOGIN，MAIL-016~019）并编译级验证 | `TcpImapTransport` / `TcpSmtpTransport` |
| Foundation Models 真实调用 | 需 iOS/macOS 26+ 真机 | `MlGateway` 端口 |
| Core ML embedding 模型接入 | 模型文件（首启 CDN 下载）+ 转换 | `EmbeddingProvider` 端口 |
| AppAuth 授权 UI 流 | 需正式 client id（见下）；XOAUTH2 SASL 载荷与 Keychain 保管**已交付**（MAIL-017/OAUTH-004） | `OAuthClientInfo` 注入位 |
| IDLE 长连接协议增强 | 轮询编排 v1 **已交付**（PollingPolicy/SyncRunner，SYNC-011）；IDLE 长连接需真机验证生命周期 | `SyncRunner` 外层 |
| golden 评测集真机跑批 | 真机 + 真实模型 | `GoldenEvaluator` |

## 4. v0.2 · UI 基准线（2026-11-08，PR #35~#39）

五个批次（docs/plan/ui-baseline-audit.md）：0 specs 对账 → 1 骨架原生化 → 2 交互闭环 → 3 反馈与性能 → 4 品味收尾。
- **原生骨架**：NavigationSplitView（可拖分栏/⌘⇧C 折叠）+ List(selection:) 键盘导航 + 完整命令面；红绿灯 hack/自绘蓝条栏/常驻诊断条全部清除
- **交互闭环**：阅读窗格四动作全部接通；Block=blocked 桶+显式规则（CLS-011）；打开即已读（本地并集 + MAIL-026 UID STORE 写回）；Demo 独立内存库+水印+退出（不污染生产库）
- **健壮与性能**：正文后台加载+失败重试；搜索 250ms 防抖+Esc；回填进度条；列表日期一次解析零重复分配（PERF-004）
- **品味**：token 全集与内联色/字号源码扫描清零；en+zh-Hans 双语（分段文案对齐规范 New/Previously seen/Set aside）；动效 token+减弱动态降级；Settings（断开连接闭环/远程图片开关/诊断）；Compose 独立窗口；App icon；a11y（label/tooltip/行朗读）
- 每批一个 PR、全程 TDD（先登记用例→红灯→实现→翻绿）；本地 + CI（8 检查）+ 真机视觉冒烟三重验证

### v0.1 追加交付（PR #13/#14，回应完成度审计）
- **生产传输层**：`NetworkTransport.swift`（TLS 连接/行读取器/字面量分片容错）+ `TcpTransports.swift`（Imap XOAUTH2·LOGIN、SMTP AUTH LOGIN、多行应答归并）——MAIL-016~019
- **Keychain 凭证保管**：`KeychainVault`（SecItem 真实路径，CI 实测读写）——OAUTH-004
- **预置名单库种子**：`RosterSeed`（42 域名 v1 种子 + CDN 热更覆盖解析，银行等歧义域不收）——CLS-009
- **轮询编排**：`PollingPolicy`（成功复位/指数退避封顶）+ `SyncRunner`——SYNC-011

## 4. 用户侧注册/准备清单（goal 要求的最终清单）

### 立即可做（本周，按 docs/launch/00 时间线）
1. **修本地开发环境**（M1 起本地跑测试与真机调试的前提）：
   `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`，
   或直接装完整 Xcode（26.x）后 `sudo xcode-select -s /Applications/Xcode.app`
2. **D-U-N-S 查询/申请**（免费、等待最长 ~2 周）：developer.apple.com/D-U-N-S，查"杭州望文生义科技有限公司"（英文译名以 D&B 现有记录为准）
3. **Apple Developer 注册材料**（¥688/年，付款可延至 M1 中）：docs/launch/01 §2
4. **Google Cloud 项目**（测试模式当天可用）：docs/launch/02 Phase 1；**实测国际卡付款**
5. **Microsoft Entra 应用注册**（免费）：docs/launch/03 Phase 1
6. **隐私政策站上线**（2 小时）：docs/launch/04 + 建议买域名（mailo.app 等）

### M2 前完成
7. Google OAuth **正式验证 + CASA**（$500-4500/年、4-6 周）：docs/launch/02 Phase 2/3（演示视频等材料清单在内）
8. Microsoft publisher 验证（视 03 文档政策核实结论决定）
9. Core ML embedding 模型选型与转换（multilingual-e5-small 档，转换脚本属运营流程）

### 上架前（M3）
10. App Store Connect 记录 + 隐私标签（"不收集数据"）+ 发布地区**不含中国大陆**
11. TestFlight 内测名单（大陆测试者可用，无需备案）

### 长期
12. Apple 年费续费 / CASA 年审（12 个月）入日历

## 5. 如何跑

```bash
# 全部测试（本地需健康工具链；CI 每次自动跑）
swift test --package-path packages/CoreKit        # 或任一包

# App（本地有 Xcode 后）
cd apps/MailoIOS && xcodegen -s project.yml && open MailoIOS.xcodeproj   # Demo 数据自动装配

# CI 同款构建
xcodebuild -project MailoIOS.xcodeproj -scheme MailoIOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
