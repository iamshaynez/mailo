# Mailo 架构方案基线 v3（SwiftUI 双端版）

> 定稿日期：2026-11-07。本文件是全部技术决策的单一事实来源（SSOT）。
> 决策演进：v1（轻量云元数据服务，Flutter 五端）→ v2（纯本地客户端，避免服务器合规成本）→ v2.1（中国大陆主体 + 分发策略）→ **v3（锁定 iOS + macOS，技术栈切 SwiftUI 原生；放弃 Android/Windows/Linux，多端期权清零）**。
> 修改本文件 = 变更决策，需在「决策记录」表追加一行并说明理由。

## 1. 项目定位

- **纯本地邮件客户端**：无用户数据服务器（静态 CDN 仅分发名单库/模型，零合规负担）
- **hey.com 式归类**：Imbox / Feed / Paper Trail / Screener / Set Aside 的组织体验，适配任意服务商
- **市场**：海外为主；运营主体为中国大陆公司
- **卖点**：无云、零数据出设备 + 智能分类

## 2. 决策记录

| # | 决策项 | 定案 | 备注 |
|---|---|---|---|
| D1 | 技术栈 | **SwiftUI + Swift 6（严格并发）**（v3 修订，原 Flutter） | 触发条件：平台锁定 Apple 双端后，多端覆盖（Flutter 第一权重）清零；Foundation Models 原生直调、Core ML embedding、菜单栏常驻、WKWebView 少一层抽象 |
| D2 | 平台 | **仅 iOS + macOS**（v3 修订，删 Android/Windows 二期） | min iOS 17 / macOS 14；Foundation Models（iOS/macOS 26+）用 `#available` 门控，老系统降级 embedding |
| D3 | 后端 | **无**（v2 修订，原为轻量云元数据服务） | 规避服务器开发/运维/数据处理合规 |
| D4 | 账号体系 | 无 | 无服务器即无账号 |
| D5 | 归类模型 | 派生视图层：不移动邮件，本地标注；可选写回服务端 label **默认关**。用户显式**删除**除外（JOURNEY-022/MAIL-027）：UID MOVE 到 Trash，属用户主动破坏性操作，非自动归类 | 保"不破坏"承诺；删除是用户意图，非系统行为 |
| D6 | 多端同步 | 邮箱即通道：`Mailo/Sync` 约定文件夹，append-only JSON + CRDT | 详见 §6 |
| D7 | iOS 后台推送 | **接受无推送**：前台 IDLE 实时 + 打开秒同步 + BGAppRefresh 尽力而为 | 零后端唯一产品级代价 |
| D8 | 分类管线 | 规则 > 名单库 > Foundation Models > embedding 原型向量 > Screener | 详见 §5 |
| D9 | 本地模型 | Foundation Models（原生 API）+ 多语言 embedding 兜底（**Core ML**，首启 CDN 下载） | 结果冻结幂等；一端推理全端共享 |
| D10 | 服务商 | Gmail（IMAP+XOAUTH2）+ Outlook（IMAP+XOAUTH2）+ 标准 IMAP 授权码 | ⚠ Gmail scope 决策点见 §4.1 |
| D11 | 研发流程 | 严格 TDD：specs 用例库 → 失败测试 → 实现 | 详见 §8 |
| D12 | 主体与分发 | 中国大陆公司主体；iOS/macOS 上 App Store **海外区（不含中国大陆）**；macOS 亦可 Developer ID+公证（v3 修订：删 Android apk 直发） | 备案义务仅由"上架国区"触发，不勾选即无义务；TestFlight 内测不需要备案（大陆测试者正规通道） |
| ~~D13~~ | ~~GMS 零依赖~~ | **已删除**（v3：无 Android，约束不再存在） | — |
| D14 | 设计语言 | **Inbox Reference Exact + Amex Blue**（v3.6，2026-11-10 修订）：保留参考图精确几何；整体中性色与行动色改为美国运通蓝 #0077C8 及深海军蓝；Logo 为 m + 圆点；邮件区为白色表面并恢复搜索/选中行/分栏柔和阴影 | 用户要求的主题与原图层次修正；不改变邮件行为。Dark 为独立扩展，动效尊重 Reduce Motion；规范见 docs/design/design-system.md |

## 3. 架构分层

```
┌─ UI 层（apps/：iOS App / macOS App，SwiftUI，薄壳）
├─ 派生层：hey 式组织（分类状态机、Screener 队列）
├─ 本地镜像层：GRDB(SQLite) + FTS5 全文索引 —— UI 唯一数据源，响应式流
├─ 域核心（Swift Package，纯 Swift，零 UI/IO 依赖）：分类管线 / 规则引擎 /
│  CRDT 合并 / MIME 解析 / 稳定主键
├─ 端口（协议）：MailStore / SyncChannel / MlEngine / CredentialVault
└─ 适配层：IMAP/SMTP+XOAUTH2/授权码（Network.framework）、Foundation Models、
   Core ML embedding、Keychain(Security.framework)
```

核心原则：
- **本地优先**：UI 只读本地库，永不阻塞网络 IO；同步引擎后台写库
- **域核心零依赖**：测试主战场在 core，毫秒级确定性
- **端口先行**：包间只依赖接口（Gmail-REST 备选路线靠它预留）

稳定主键：邮件关联键用 **Message-ID + 账号指纹**，不用 IMAP UID（UIDVALIDITY 会重置）。

## 4. 协议栈

IMAP/SMTP 家族 + 三种鉴权（Gmail XOAUTH2 / Outlook XOAUTH2 / 授权码）。Gmail 特性经 `X-GM-LABELS` / `X-GM-THRID` 扩展。
协议核心自建（纯 Swift 解析器，与传输解耦；Network.framework 起步，必要时迁 SwiftNIO）；**MailCore2 作参考实现与对照测试 oracle**。覆盖 QRESYNC/CONDSTORE、IDLE、能力协商矩阵（残缺行为：无 CONDSTORE、GBK 主题、UIDVALIDITY 重置——契约测试逐项覆盖）。

### 4.1 ⚠ Gmail scope 决策点（M1 末复核）

Gmail IMAP+XOAUTH2 **只接受全量 scope** `https://mail.google.com/`（授权屏显示"永久删除所有邮件"级别）；窄权限仅 Gmail REST API 可用。两条路都要 CASA，差异只在用户信任。**动作**：M1 末用真实 consent 屏截图复核；不可接受则 Gmail 单走 REST 适配器（端口已预留）。

## 5. 分类管线

```
新邮件 → ① 用户规则（最高优先级，永远赢）
       → ② 预置名单库（域名/发件人级；app 版本更新 + 静态 CDN 热更）
       → ③ Foundation Models（guided generation 结构化输出，temp=0；仅 Apple Intelligence 设备）
       → ④ embedding 原型向量兜底（多语言，Core ML，首启 CDN 下载）
       → ⑤ 置信度不足 → Screener 待定（宁可待定，不可错分）
```

- 手动纠正 → **生成显式规则**（非隐式学习）：可解释、可同步、纯数据 TDD 友好
- **结果冻结幂等**：同一封邮件永不重推
- **一端推理、全端共享**：首收设备推理一次，结果经 §6 通道同步
- **原型向量，不用向量库**：每类目 K 个原型（预置种子 + 用户确认邮件滚动更新），余弦 Top-K 投票；置信度直接驱动 ⑤
- **回填策略**：名单库先兜大头，模型跑长尾；首屏最近窗口（50 封）优先，历史按需拉取（列表滚动到底触发，SYNC-016 v2/018；批间节流 200ms，正文走独立连接通道 JOURNEY-023）
- 可测性：MlEngine 端口注入，单测/集成测全用录制 mock；真实模型只进真机 e2e 抽样 + golden 评测集门禁

## 6. 多端同步（邮箱即通道）

元数据 = 分类结果、用户规则、自定义名单、Screener 决策。

- **载体**：用户邮箱内约定文件夹 `Mailo/Sync`，append-only JSON 条目
- **条目**：`{id, device_id, ts, type, payload}`；tombstone 删除；定期快照压缩防膨胀
- **冲突**：CRDT——规则 LWW（带时间戳）、分类结果 first-writer-wins
- **写节流**：本地队列 30s 或 20 条 flush（避开服务器 append 限额）
- **无需加密**：能读该文件夹者本就能读全部邮件，分类元数据无增量泄露面
- 代价：同步延迟 = IMAP 同步周期；网页端可见该文件夹（产品沟通点）
- 已否决：iCloud CloudKit（当年否决理由已随多端取消而减弱，但仍否决——引入它等于引入"苹果生态内后端"，且与 `Mailo/Sync` 双通道徒增复杂度）

## 7. 性能与体验

- GRDB + FTS5（中文 trigram tokenizer，M1 早期验证）
- SwiftUI 原生列表虚拟化；HTML 邮件 WKWebView 沙箱渲染，默认禁远程图片，链接安全审查——独立契约测试面
- macOS：菜单栏常驻 + IDLE（原生一等公民，v3 切换的甜头之一）
- 动画性能进 CI：脚本化滚动 1 万封列表采样 jank/hitch 率（XCTest Metrics），趋势门禁
- 大邮箱导入（10 万封）分批回填 + 优先级调度
- 系统集成顺带收益：Spotlight 索引邮件（数据仍在设备，零合规）

## 8. TDD 与研发流程

测试金字塔（多→少，快→慢）：
1. **域核心单测**（数千，毫秒级）：Swift Testing；分类/规则/CRDT/MIME 纯函数
2. **同步引擎集成**：跑在自研**进程内假 IMAP 服务器**（Swift 实现，Network.foundation，测试进程内嵌，快）——本项目最重要的基建投资
3. **契约测试**：Gmail/Outlook/QQ/163 真实会话 cassette（脱敏录制），锁死服务商怪癖矩阵
4. **E2E 旅程**：XCUITest，数量克制，仅用户旅程级；快照测试（swift-snapshot-testing）锁 UI 回归

用例管理（specs/）：
- 能力域编号：CLS 分类 / SYNC 同步 / MAIL 协议 / PERF 性能 / JOURNEY 旅程
- 表驱动 markdown 用例 + ID（如 `CLS-014 未知发件人首封进 Screener`），测试代码以 ID 命名引用，双向可追溯
- 流程：specs 加用例 → 写失败测试 → 实现 → 用例翻绿

## 9. 仓库结构（Agent 上下文最小化）

```
apps/
  MailoIOS/       # XcodeGen project.yml + SwiftUI 壳
  MailoMac/       # 同上，菜单栏常驻
packages/         # SwiftPM 包（Agent 只改 yaml/源码，不碰 pbxproj）
  CoreKit/        # 纯 Swift 域核心（零 UI/IO）
  MailProtoKit/   # IMAP 适配器 + 假服务器 + 契约 cassette
  SyncKit/        # SyncChannel 实现（Mailo/Sync）
  MlKit/          # MlEngine 端口 + mock + Foundation Models/Core ML 实现
  UiKit/          # 共享 SwiftUI 组件与动画
specs/            # 用例库（单一事实来源）
docs/             # plan / launch 文档
```

- 工程文件由 **XcodeGen** 从 `project.yml` 生成（pbxproj 格式敏感，是 Agent 开发雷区，禁手改）
- 每 feature 目录自包含（spec + tests + impl + README）；任务定义为"使 spec X 用例全绿"，Agent 只需装载一个目录
- CI：GitHub Actions macOS runner（测试）；打包后期可上 Xcode Cloud
- AGENTS.md 写仓库地图与约定

## 10. 路线图

- **M0（~4 周，地基）**：SwiftPM monorepo + XcodeGen + CI + specs 规范 + 假 IMAP 服务器 + 域核心骨架（MIME/分类管线/CRDT 纯函数 + 第一批红灯测试）。**并行启动上架四线**（docs/launch/00）
- **M1（~6 周，单端打穿）**：iOS+macOS，授权码账号全旅程——收发、分类呈现、Screener、手动纠正生成规则、FTS 搜索、embedding 兜底。M1 末：Gmail consent 屏复核（§4.1）；SwiftUI 双端适配差异盘点（菜单/窗口/快捷键）
- **M2（~5 周，多端成体）**：`Mailo/Sync` 同步落地 + Gmail/Outlook XOAUTH2 接入（测试模式内测）+ 提交 Google 验证/CASA、视核实结果决定 MS publisher 验证
- **M3（~4 周，打磨上架）**：动画门禁、大邮箱性能门禁、golden 评测集门禁、Apple 审核提交（海外区）

## 11. 风险清单

| # | 风险 | 对策 |
|---|---|---|
| R1 | Google CASA 周期/费用（$500-4500/年，4-6 周，年审） | M0 测试模式先行，M2 提交；材料清单见 docs/launch/02 |
| R2 | Gmail 全量 scope 的 consent 屏流失 | §4.1 决策点，REST 备选已预留 |
| R3 | Microsoft 第三方 MSA 政策收紧 | docs/launch/03 政策核实三步法，Graph 备选已预留 |
| R4 | iOS 无后台推送的用户预期管理 | 定位为隐私卖点；打开秒同步 |
| R5 | HTML 邮件渲染工时黑洞 | 独立契约测试面，M1 提前验证 |
| R6 | Foundation Models 非确定性 | 结果冻结 + golden 门禁 |
| R7 | 假 IMAP 服务器基建被砍 | 明确为 M0 交付物，先于同步引擎本身 |
| R8 | SwiftUI 双端差异工作量（菜单/窗口/键盘/尺寸类）被低估 | M1 双端同时打穿（非先 iOS 后补 mac），差异第一时间暴露 |
| R9 | 大陆主体的国际付款摩擦（Google Cloud 结算、CASA 美元） | M0 第一周实测国际卡；备选外币卡/香港卡 |
| — | ~~App 备案（apk 直发）/ GMS 零依赖~~ | **已随 Android 取消而消除**（v2.1 的 R8/R9/D13 作废，05 文档已删） |
