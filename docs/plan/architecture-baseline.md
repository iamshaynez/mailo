# Mailo 架构方案基线 v2（零后端版）

> 定稿日期：2026-11-07。本文件是全部技术决策的单一事实来源（SSOT）。
> 决策演进：v1（轻量云元数据服务）→ v2（纯本地客户端，避免服务器合规成本）。
> 修改本文件 = 变更决策，需在「决策记录」表追加一行并说明理由。

## 1. 项目定位

- **纯本地邮件客户端**：无用户数据服务器（静态 CDN 仅分发名单库/模型，零合规负担）
- **hey.com 式归类**：Imbox / Feed / Paper Trail / Screener / Set Aside 的组织体验，适配任意服务商
- **市场**：海外为主
- **卖点**：无云、零数据出设备 + 智能分类

## 2. 决策记录

| # | 决策项 | 定案 | 备注 |
|---|---|---|---|
| D1 | 技术栈 | Flutter 单代码库 | iOS/Android/macOS/Windows/Linux 可达；IMAP 库薄弱 = 自建协议核心，恰好落在 TDD 域核心层 |
| D2 | 首发平台 | iOS + macOS | 共享 Keychain/APNs/沙箱经验；Android/Windows 二期复用核心零改动 |
| D3 | 后端 | **无**（v2 修订，原为轻量云元数据服务） | 规避服务器开发/运维/数据处理合规；代价见 D7 |
| D4 | 账号体系 | 无（v2 修订，原为独立账号） | 无服务器即无账号 |
| D5 | 归类模型 | 派生视图层：不移动邮件，本地标注；可选写回服务端 label **默认关** | 保"不破坏"承诺 |
| D6 | 多端同步 | 邮箱即通道：`Mailo/Sync` 约定文件夹，append-only JSON + CRDT | 详见 §6 |
| D7 | iOS 后台推送 | **接受无推送**：前台 IDLE 实时 + 打开秒同步 + BGAppRefresh 尽力而为 | 零后端唯一产品级代价，已拍板 |
| D8 | 分类管线 | 规则 > 名单库 > Foundation Models > embedding 原型向量 > Screener | 详见 §5 |
| D9 | 本地模型 | 平台原生优先（Apple Foundation Models）+ 多语言 embedding 兜底（首启下载） | 结果冻结幂等；一端推理全端共享 |
| D10 | 服务商 | Gmail（IMAP+XOAUTH2）+ Outlook（IMAP+XOAUTH2）+ 标准 IMAP 授权码 | ⚠ Gmail scope 决策点见 §4.1 |
| D11 | 研发流程 | 严格 TDD：specs 用例库 → 失败测试 → 实现 | 详见 §8 |

## 3. 架构分层

```
┌─ UI 层（apps/，薄壳：路由、动画、平台胶水）
├─ 派生层：hey 式组织（分类状态机、Screener 队列）—— 本客户端的"面子"
├─ 本地镜像层：SQLite(Drift) + FTS 全文索引 —— UI 唯一数据源，响应式流
├─ 域核心（packages/core，纯 Dart，零 IO）：分类管线 / 规则引擎 /
│  CRDT 合并 / MIME 解析 / 稳定主键
├─ 端口（接口）：MailStore / SyncChannel / MlEngine / CredentialVault / PushProvider(预留)
└─ 适配层（实现）：IMAP/SMTP+XOAUTH2/授权码、Foundation Models、embedding、Keychain
```

核心原则：
- **本地优先**：UI 只读本地库，永不阻塞网络 IO；同步引擎后台写库
- **域核心零依赖**：所有测试主战场在 core，毫秒级确定性
- **端口先行**：包间只依赖接口，实现可替换（Gmail-REST、Graph 备选路线靠它预留）

稳定主键：邮件关联键用 **Message-ID + 账号指纹**，不用 IMAP UID（UIDVALIDITY 会重置）。

## 4. 协议栈

单栈收敛：IMAP/SMTP 家族 + 三种鉴权（Gmail XOAUTH2 / Outlook XOAUTH2 / 授权码）。

Gmail 特性经 `X-GM-LABELS` / `X-GM-THRID` 扩展（label 读写、线程视图）。
协议核心自建（Dart 生态无成熟库）：QRESYNC/CONDSTORE 增量、IDLE、能力协商矩阵（服务器残缺行为：无 CONDSTORE、GBK 编码主题、UIDVALIDITY 重置——契约测试逐项覆盖）。

### 4.1 ⚠ Gmail scope 决策点（M1 末复核）

Gmail IMAP+XOAUTH2 **只接受全量 scope** `https://mail.google.com/`（授权屏显示"永久删除所有邮件"级别）；窄权限（`gmail.readonly` 等）仅 Gmail REST API 可用。两条路都要 CASA 验证，差异只在用户信任。

**动作**：M1 末用真实 consent 屏截图复核流失风险；不可接受则 Gmail 单独走 REST 适配器（端口已预留）。Outlook 不受影响。

## 5. 分类管线

```
新邮件 → ① 用户规则（最高优先级，永远赢）
       → ② 预置名单库（域名/发件人级；app 版本更新 + 静态 CDN 热更）
       → ③ Apple Foundation Models（guided generation 结构化输出，temp=0；仅 Apple Intelligence 设备）
       → ④ embedding 原型向量兜底（多语言，首启 CDN 下载）
       → ⑤ 置信度不足 → Screener 待定（宁可待定，不可错分）
```

- 手动纠正 → **生成显式规则**（非隐式学习）：可解释、可同步、纯数据 TDD 友好
- **结果冻结幂等**：同一封邮件永不重推（Foundation Models 非确定性的对策）
- **一端推理、全端共享**：首个收到邮件的设备推理一次，结果经 §6 通道同步，其他设备不重推（模型碎片化被隔离到新邮件首分那一刻；老设备靠它白拿分类结果）
- **embedding 用原型向量，不用向量库**：每类目维护 K 个原型向量（预置种子 + 用户已确认邮件滚动更新），新邮件余弦 Top-K 投票出类别+置信度；零 ANN 基础设施、增量自学习、置信度直接驱动 ⑤
- **回填策略**：名单库先兜大头（订阅类发件人高度集中，80%+ 可命中），模型只跑长尾；最近 90 天优先、后台批处理
- 可测性：MlEngine 端口注入，单测/集成测全用录制 mock；真实模型只进真机 e2e 抽样 + golden 评测集（数百封标注邮件，发版前真机准确率门禁）

## 6. 多端同步（邮箱即通道）

元数据 = 分类结果、用户规则、自定义名单、Screener 决策。

- **载体**：用户邮箱内约定文件夹 `Mailo/Sync`，append-only JSON 条目
- **条目格式**：`{id, device_id, ts, type, payload}`；tombstone 删除；定期快照压缩防膨胀
- **冲突解决**：CRDT——规则 LWW（带时间戳）、分类结果 first-writer-wins（与"冻结幂等"一致）
- **写节流**：本地队列 30s 或 20 条 flush（避开服务器 append 限额）
- **无需加密**的论证：能读该文件夹者本就能读全部邮件，分类元数据无增量泄露面
- 代价：同步延迟 = IMAP 同步周期；网页端可见该文件夹（产品沟通点）
- 已否决备选：iCloud CloudKit（锁 Apple 生态）、用户自配网盘（非主流用户不可用）

## 7. 性能与体验

- 本地 SQLite 镜像 + Drift 响应式流；FTS5 全文搜索（中文 trigram/分词方案 M1 早期验证）
- 列表虚拟化分页；HTML 邮件各端 WebView 沙箱渲染，默认禁远程图片（隐私+性能+防追踪），链接安全审查——单独契约测试面
- 动画性能进 CI：脚本化滚动 1 万封列表采样 jank 率，趋势门禁
- 大邮箱导入（10 万封）分批回填 + 优先级调度
- macOS：常驻进程天然在线（菜单栏 + IDLE）

## 8. TDD 与研发流程

测试金字塔（多→少，快→慢）：
1. **域核心单测**（数千，毫秒级）：分类/规则/CRDT/MIME 纯函数
2. **同步引擎集成**：跑在自研**进程内假 IMAP 服务器**（可注入残缺行为）——本项目最重要的基建投资
3. **契约测试**：Gmail/Outlook/QQ/163 真实会话 cassette（脱敏录制），锁死服务商怪癖矩阵
4. **E2E 旅程**（Patrol，数量克制）：仅用户旅程级

用例管理（specs/）：
- 能力域编号：CLS 分类 / SYNC 同步 / MAIL 协议 / PERF 性能 / JOURNEY 旅程
- 表驱动 markdown 用例 + ID（如 `CLS-014 未知发件人首封进 Screener`），测试代码以 ID 命名引用，双向可追溯
- 流程：specs 加用例 → 写失败测试 → 实现 → 用例翻绿

## 9. 仓库结构（Agent 上下文最小化）

```
apps/            # ios / macos 壳（薄）
packages/
  core/          # 纯 Dart 域核心（零 IO）
  mail_proto/    # IMAP 适配器 + 假服务器 + 契约 cassette
  sync/          # SyncChannel 实现（Mailo/Sync 方案）
  ml/            # MlEngine 端口 + mock + apple_foundation + embedding 实现
  ui_kit/        # 组件与动画
specs/           # 用例库（单一事实来源）
docs/            # plan / launch 文档
```

每 feature 目录自包含（spec + tests + impl + README）；任务定义为"使 spec X 用例全绿"，Agent 只需装载一个目录。AGENTS.md 写仓库地图与约定。

## 10. 路线图

- **M0（~4 周，地基）**：monorepo + CI + specs 规范 + 假 IMAP 服务器 + 域核心骨架（MIME/分类管线/CRDT 纯函数 + 第一批红灯测试）。**并行启动上架四线**（见 docs/launch/00）
- **M1（~6 周，单端打穿）**：iOS+macOS，授权码账号全旅程——收发、分类呈现、Screener、手动纠正生成规则、FTS 搜索、embedding 兜底。M1 末：Gmail consent 屏复核（§4.1）
- **M2（~5 周，多端成体）**：`Mailo/Sync` 同步落地 + Gmail/Outlook XOAUTH2 接入（测试模式内测）+ 提交 Google 验证/CASA、视核实结果决定 MS publisher 验证
- **M3（~4 周，打磨上架）**：动画门禁、大邮箱性能门禁、golden 评测集门禁、Apple 审核提交
- Android/Windows：M2 后启动，核心零改动

## 11. 风险清单

| # | 风险 | 对策 |
|---|---|---|
| R1 | Google CASA 周期/费用（$500-4500/年，4-6 周，年审） | M0 测试模式先行，M2 提交；材料清单见 docs/launch/02 |
| R2 | Gmail 全量 scope 的 consent 屏流失 | §4.1 决策点，REST 备选已预留 |
| R3 | Microsoft 第三方 MSA 政策收紧（社区已有限流信号） | docs/launch/03 政策核实三步法，Graph 备选已预留 |
| R4 | iOS 无后台推送的用户预期管理 | 定位为隐私卖点；打开秒同步 |
| R5 | HTML 邮件渲染工时黑洞 | 独立契约测试面，M1 提前验证 |
| R6 | Foundation Models 非确定性 | 结果冻结 + golden 门禁 |
| R7 | 假 IMAP 服务器基建被砍 | 明确为 M0 交付物，先于同步引擎本身 |
