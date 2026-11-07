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
| UI | `DesignKit` | 设计规范 token（hex 常量化防漂移）、三栏壳（NavigationSplitView，212/392/3pt 选中条）、AppModel 端到端装配（同步→入库→分类→呈现，进程内零网络） | JOURNEY-001, DESIGN-001 |
| App | `apps/MailoIOS` `apps/MailoMac` | XcodeGen 工程，CI 构建（iOS 模拟器 + macOS）通过；bundle id `com.xiaowenz.mailo` | — |
| 门禁 | CI | 8 项必需检查：6 包 swift-test × 矩阵 + 双端 app-build；main 保护（PR-only、enforce_admins、仅 squash）；PERF 吞吐门禁 | PERF-001/002 |

**用例总计**：42 条（41 green + 快照外其余全实现），见 `docs/specs/`。

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
| 真实 TCP/TLS 传输（Network.framework） | 需真机/真实账号联调 | `ImapTransport`/`SmtpTransport` 端口，Fake 实现同构替换 |
| Foundation Models 真实调用 | 需 iOS/macOS 26+ 真机 | `MlGateway` 端口 |
| Core ML embedding 模型接入 | 模型文件（首启 CDN 下载）+ 转换 | `EmbeddingProvider` 端口 |
| AppAuth 授权 UI 流 | 需正式 client id（见下） | `OAuthClientInfo` 注入位 |
| Keychain 生产实现 | 需 app target 链接 | `CredentialVault` 端口（Security.framework） |
| 预置名单库数据 | 运营内容（域名→桶种子数据） | `Roster` 数据结构 |
| IDLE 长连接/后台调度 | 需真机验证生命周期 | 引擎 sync 循环外层 |
| golden 评测集真机跑批 | 真机 + 真实模型 | `GoldenEvaluator` |

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
