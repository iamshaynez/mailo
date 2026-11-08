# UI/UX 基准线审计与批次计划（v1）

> 定稿：2026-11-08。本文是「把 Mailo 从 hero-path demo 抬到成熟高品质 Mac 原生应用」的
> 基准线总账：审计结论 + 五个批次的执行计划。后续功能开发以本基准线为起点。
> 决策依据：docs/design/design-system.md（Blue Box Classic v1）、docs/plan/architecture-baseline.md（D14/D11）。

## 0. 已定决策（本文档生效即生效）

| # | 决策 | 理由 |
|---|---|---|
| UB-1 | 三栏骨架迁 `NavigationSplitView`，蓝条栏改为系统 toolbar 着色 | 修掉红绿灯 spacer hack 的唯一正路；白送可拖分栏/侧栏折叠/⌘⇧C；Blue Box 身份靠 `toolbarBackground(brandBlue)` + 配色与选中态保留 |
| UB-2 | 界面语言：**默认英文**，简体中文为第一翻译语言（String Catalog） | 主市场海外（基线 D12）；hey 式标签本就是英文造词；xcstrings 随包分发，系统语言自动切换 |
| UB-3 | 已读标记：本地镜像 flags 即时更新 + IMAP `UID STORE` 服务器写回（尽力而为，失败不阻塞 UI） | 本地优先架构的惯例路径；D5 只约束「归类元数据」不写回，`\Seen` 是用户邮件状态本身 |
| UB-4 | Demo 模式：独立内存库装配 + 顶条水印 + 可退出，**永不触碰生产 `mailo.sqlite`** | 现状 demo 数据混入真实库是数据污染缺陷 |
| UB-5 | 视觉回归网用「模型层断言 + DesignKit swift-testing」先立，像素快照门禁（对 OS 渲染敏感）延后与 M3 动画门禁同批 | CI runner 与本地 OS 渲染差异会让像素快照变 flake 工厂 |

## 1. 审计结论（2026-11-08，main@951363f）

现状 = **mockup 的忠实转录 + 真实管线**：色彩 token 纪律好（DESIGN-001 锁测试）、
WKWebView 沙箱扎实、装配模型协议注入干净。差距四层：

### A. Mac 原生骨架缺失（结构性）
- 菜单栏 100% 默认（无 `.commands`）；⌘K 是纯装饰文本；列表行 `onTapGesture` 不可键盘导航
- 自绘标题栏 + 红绿灯字面 spacer（MailoShell.swift:82-84）；手绘 HStack 固定三栏不可拖动
- 诊断条（schemaDiagnostics）常驻生产 UI；无 Settings 场景；无 app icon/entitlements
- 窗口无默认尺寸/frame autosave；Compose 用 sheet 而非独立窗口（Mail.app 惯例）

### B. 交互闭环断裂
- Reply/Forward/Set Aside/⋯ 四按钮空闭包（MailReaderView.swift:65,111）
- 打开邮件不标已读；Block 无真实语义（re-freeze 回 screener）且计数不减
- 规范 §8 的「This isn't Imbox →」常驻纠正入口缺失；无 context menu；无 undo
- Demo 数据写进生产库；搜索每键直查无防抖、搜索结果行 bucket 硬编码
- 阅读页头像/bucket 用 `selectedBucket` 而非邮件自身 bucket；附件只显示文件名

### C. 状态反馈与性能
- 正文拉取在 MainActor 同步执行（mailDetail→fetchBody），无 loading/错误/重试
- `try?` 吞掉 load/decideScreener 错误；回填进度对用户不可见
- 每行新建 2-3 个 DateFormatter（DateFormatter 是贵对象，万封级滚动即 jank）
- `LazyVStack` 手绘分组放弃系统虚拟化；GeometryReader 包全树

### D. 设计系统落地缺口
- token 只有颜色+4 个布局数：排版阶梯/圆角/间距/阴影/动效时长全部未 token 化（~20 处内联字号）
- 7 处内联 Color 绕过 token 且与规范有微差（隐私徽章 #2E6B33≠#2E7D32 等）
- `selectionBarWidth` token 存在却被硬编码绕过；分段文案 New/Seen/All ≠ 规范
- 动效规范 0% 落地；零 accessibility（无 label/无 .help/无 Dynamic Type）；中英混排 + 繁体错字「進度」

### E. 测试与流程债
- 全部 JOURNEY/DESIGN Status 停在 draft（测试早已通过，第 3 步没走）；JOURNEY-006 缺 Status/Tests 行
- specs README 域表缺 STORE/ML/OAUTH/DESIGN；DELIVERY.md「NavigationSplitView」失实
- 零 #Preview、零 XCUITest

## 2. 批次计划（每批一个 PR，全程 TDD：先登记用例→红灯→实现→翻绿）

> **执行结果（2026-11-08 收官）**：五批全部合入 main——PR #35（批次 0）/ #36（1）/ #37（2）/ #38（3）/ #39（4）。
> 多语言实机验证：中文界面横幅/侧栏/分段/空态/进度全部生效，桶名按设计保留英文（DESIGN-003）。
> CI 实测修正一处工具链差异：lproj 目录名在 runner 上被规范为小写（zh-hans），L10n 两级查找兼容。

| 批次 | 主题 | 新增用例 | 关键交付 |
|---|---|---|---|
| **0** | 对账 | — | 本文档；既有用例翻绿；README/DELIVERY 修正；全量 draft 用例登记 |
| **1** | 骨架原生化 | JOURNEY-008/009 | NavigationSplitView + List selection 键盘导航 + `.commands` 菜单（⌘N/⌘R/⌘K/⌘⇧U…）+ 窗口默认尺寸/frame autosave + 诊断条撤出生产 UI |
| **2** | 交互闭环 | JOURNEY-010~013、017；CLS-011；STORE-010；MAIL-026 | Reply/Forward 预填、Set Aside 真实现、打开即已读（本地+STORE 写回）、Block=blocked 桶、常驻纠正入口、context menu、undo、demo 隔离 |
| **3** | 反馈与性能 | JOURNEY-014/015；PERF-004；SYNC-017 | 正文异步加载+错误重试、日期一次解析缓存（行渲染零 formatter 分配）、搜索防抖+Esc、回填进度呈现、行 hover 态 |
| **4** | 品味收尾 | DESIGN-002/003/004；JOURNEY-016 | token 全集（排版/圆角/间距/阴影/动效）+ 消灭内联色、xcstrings 多语言（en 默认+zh-Hans）、a11y 全覆盖（label/.help/Dynamic Type/reduceMotion）、动效落地、Settings ⌘,、Compose 独立窗口、App icon |

排序原则：骨架先行（后面所有项骑在上面）→ 把视觉模型变成应用 → 健壮性 → 抛光。

## 3. 明确不在本基准线内（延后项）

- 深色模式（规范 §7：M3 后另立 v2 规范；mockup B 为候选）
- 菜单栏常驻 MenuBarExtra + IDLE 长连接（基线 §7 路线图项）
- 像素级快照门禁与滚动 jank 采样（M3 动画门禁同批，UB-5）
- iOS 专属适配（底部 bucket 栏等，M1 后段 iOS mockup 再审）
- Gmail 供应商接入与授权屏复核（M2 线）
