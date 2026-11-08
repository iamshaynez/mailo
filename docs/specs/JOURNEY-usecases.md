# JOURNEY · 用户旅程与装配用例

## JOURNEY-001 骨架端到端装配（同步→镜像→分类→呈现）
- **Given** FakeImapServer 带 3 封邮件（roster 可命中 2 封 + 未知发件人 1 封），MailoAppModel.bootstrap
- **When** 同步引擎拉取 → 镜像入库 → 管线分类（名单库命中 + 模型低置信待定）→ 冻结 → 加载 bucket 列表
- **Then** imbox 列表含 roster 判定的邮件；低置信未知件计入 Screener 待定；全程零网络（进程内）
- **Status**: green
- **Tests**: `journey_001_bootstrap_end_to_end`

## DESIGN-001 设计 token 与规范一致
- **Given** docs/design/design-system.md 的关键值
- **When** 读取 DesignTokens
- **Then** brand 蓝 #006FCF、五 bucket 语义色、三栏宽 212/392、选中蓝条 3pt 与规范一致（防漂移）
- **Status**: green
- **Tests**: `design_001_tokens_match_spec`

## JOURNEY-002 真实账户装配路径（注入传输）
- **Given** AppModel.connect(account:transport:) 以 FakeImapServer 为注入传输（CI 可测，生产注入 TcpImapTransport）
- **When** 走完整装配：设备码授权（生产）→ 连接 → 同步 → 入库 → RosterSeed 分类 → 冻结 → 列表
- **Then** feed/paperTrail/imbox 各桶正确呈现；未知发件人低置信进 Screener 计数；本地库为文件路径模式（跨启动持久）
- **Status**: green
- **Tests**: `journey_002_real_account_assembly`

## JOURNEY-003 邮件详情与未读呈现
- **Given** 已入库邮件（含完整 raw 字节）
- **When** mailDetail(stableId) 与列表渲染
- **Then** 详情含完整正文（从 raw 重新解析，非 200 字 snippet）；未读判定 = flags 不含 \\Seen（列表"New"分段依据）
- **Status**: green
- **Tests**: `journey_003_detail_and_unread`

## JOURNEY-004 HTML 邮件详情分离与沙箱渲染
- **Given** 一封 HTML-only 邮件（无 text/plain 部分）
- **When** mailDetail
- **Then** textBody 为 nil、htmlBody 携带 HTML 原文；渲染层用 WKWebView + CSP（default-src 'none'; style-src 'unsafe-inline'; img-src data:）——远程图片默认禁（规范 §7），纯文本邮件仍走原生 Text
- **Status**: green
- **Tests**: `journey_004_html_detail_separated`

## JOURNEY-005 refresh token 恢复会话（免授权）
- **Given** 上次连接成功：账户信息（email/clientId/账户形态）已存本地、refresh token 已存 vault
- **When** App 重启执行 restoreSavedAccount（token 刷新注入 + 传输工厂注入，均可测）
- **Then** 免设备码直接完成"刷新→连接→增量同步"；无存档或刷新失败返回 false（回设置页）
- **Status**: green
- **Tests**: `journey_005_restore_session`

## JOURNEY-006 撰写并发送（compose）
- **Given** 已连接账户（vault 有 refresh token；token 刷新与 SMTP 传输均为注入点）
- **When** composeAndSend(to:subject:body:)
- **Then** 刷新 access token → SMTP XOAUTH2 会话 → 发出 DATA（点填充）→ 状态反馈成功；失败带错误信息
- **Status**: green
- **Tests**: `journey_006_compose`

## JOURNEY-007 全文搜索呈现
- **Given** 已入库邮件（含中文主题）
- **When** AppModel.search("关键词")
- **Then** 返回命中行（FTS/底层搜索映射）；UI 搜索框输入即搜、清空恢复列表
- **Status**: green
- **Tests**: `journey_007_search_results`

---

> 以下为 UI 基准线批次新增用例（docs/plan/ui-baseline-audit.md 批次 1-4），实现前保持 draft。

## JOURNEY-008 三栏骨架原生化（NavigationSplitView + 键盘导航）
- **Given** 已连接（或 demo）状态的三栏主界面
- **When** 渲染主壳
- **Then** 骨架用 `NavigationSplitView`（侧栏可折叠 ⌘⇧C、分栏可拖动、窄屏自动单栏）；邮件列表用 `List(selection:)`——↑↓ 移动选中、↩ 在阅读窗格打开；不再有自绘红绿灯 spacer；标题工具栏以 brandBlue 着色承载搜索与 Compose
- **Status**: green
- **Tests**: `journey_008_splitview_skeleton`

## JOURNEY-009 菜单与快捷键（Mac 第一公民）
- **Given** 主窗口活动状态
- **When** 触发菜单/快捷键：⌘N 新邮件、⌘K 聚焦搜索、⌘R 回复、⌘⇧F 转发、⌘⇧U 标未读、⌘S Set Aside、同步 Now
- **Then** 每个快捷键路由到对应动作（无选中邮件时禁用对应项）；⌘K 聚焦搜索框（装饰性 ⌘K 徽章废除）
- **Status**: green
- **Tests**: `journey_009_menu_shortcuts`

## JOURNEY-010 Demo 隔离（不污染生产库）
- **Given** 生产库 mailo.sqlite 存在且含真实数据
- **When** 进入 Demo（「先看看」）
- **Then** demo 装配到独立内存库（MirrorStore() 无路径）；生产库字节不变；界面常驻 Demo 水印；可一键退出回到账户页；再次进入真实账户不受 demo 影响
- **Status**: green
- **Tests**: `journey_010_demo_isolation`

## JOURNEY-011 Reply / Forward 预填撰写
- **Given** 阅读窗格打开邮件 X（发件人 sender@x.co，主题 "Hello"）
- **When** 点 Reply（或 ⌘R）
- **Then** 打开撰写：To=sender@x.co、Subject="Re: Hello"、正文引用 X 的文本；Forward（⌘⇧F）Subject="Fwd: Hello"、To 空；发送走既有 JOURNEY-006 通道
- **Status**: green
- **Tests**: `journey_011_reply_forward_prefill`

## JOURNEY-012 Set Aside 操作
- **Given** 阅读任意桶内邮件 X
- **When** 点 Set Aside（或 ⌘S、右键菜单）
- **Then** X 冻结更新为 setAside 桶；当前列表移除该行、侧栏 Set Aside 计数 +1；再次进入 Set Aside 桶可见 X；⌘Z 撤销（回到原桶）
- **Status**: green
- **Tests**: `journey_012_set_aside`

## JOURNEY-013 打开即标已读（本地 + 服务器写回）
- **Given** 未读邮件 X（flags 不含 \Seen）
- **When** 阅读窗格打开 X
- **Then** 本地镜像 flags 并入 \Seen（未读点消失、New 段移出）；向服务器发 UID STORE +FLAGS (\Seen)（尽力而为：demo/假服务器生效；真实服务器失败不阻塞 UI、不回滚本地）
- **Status**: green
- **Tests**: `journey_013_mark_seen_on_open`

## JOURNEY-014 正文异步加载（不阻塞主线程）
- **Given** 正文未回填的邮件 X（raw 为空，需网络拉 BODY）
- **When** 打开 X
- **Then** 阅读窗格先渲染头部 + loading 态；正文在后台线程拉取；失败显示错误与「重试」按钮；期间 UI 可交互（主线程无网络等待）
- **Status**: green
- **Tests**: `journey_014_async_body_load`

## JOURNEY-015 搜索防抖与取消
- **Given** 搜索框连续输入
- **When** 每次键入
- **Then** 250ms 防抖后才触发查询；新键入取消未完成的上一轮；Esc 清空搜索并恢复列表
- **Status**: green
- **Tests**: `journey_015_search_debounce`

## JOURNEY-016 Settings 场景（⌘,）
- **Given** 已连接应用
- **When** 打开设置（⌘,）
- **Then** 提供账户页（邮箱、断开连接/重新连接）、隐私页（远程图片默认开关）、诊断页（schema 诊断、最近同步摘要）；断开连接清除本地凭证与账户记录并回到账户页
- **Status**: green
- **Tests**: `journey_016_settings_scene`

## JOURNEY-017 手动纠正常驻入口（This isn't Imbox →）
- **Given** 阅读窗格打开桶 B 内邮件 X（发件人 sender@x.co）
- **When** 点「Not <B> →」选择目标桶 T
- **Then** 生成 senderExact→T 显式规则（CLS-006 语义）；X 与该发件人既有待定邮件全部移入 T；下一封同发件人直接进 T
- **Status**: green
- **Tests**: `journey_017_manual_correction_entry`

## DESIGN-002 token 全集与内联色清零
- **Given** 设计规范 §2-§6 的完整 token 表（排版 8 档/圆角 4 档/间距/阴影/状态色/blueBorder/surfaceWash/hairline）
- **When** 读取 DesignTokens
- **Then** 全部 token 有常量定义并被视图引用；视图层用户可见的颜色/字号零内联字面量；privacy 徽章等 7 处历史内联色改走 token（值与规范一致）
- **Status**: green
- **Tests**: `design_002_full_token_set`

## DESIGN-003 多语言（默认英文 + 简体中文）
- **Given** String Catalog（Localizable.xcstrings）随 DesignKit 分发，开发语言 en
- **When** 系统语言为 en / zh-Hans / 其他
- **Then** en 与 zh-Hans 显示对应语言；其他语言回落英文；用户可见文案（含 Bucket 名、空态、按钮、错误）全部经 catalog 取出（零硬编码直出）；列表分段文案与规范一致（New / Previously seen / Set aside）
- **Status**: green
- **Tests**: `design_003_localization`

## DESIGN-004 动效规范落地
- **Given** 规范 §6：微交互 120ms / 转场 220ms / 归类 320ms spring(0.32, 0.86)，动画只表达归类语义
- **When** 桶切换、Screener 决策、选中变化
- **Then** 对应动效以 token 时长/曲线执行；「减弱动态效果」开启时降级为无动画
- **Status**: green
- **Tests**: `design_004_motion_tokens`

## JOURNEY-018 分段成员稳定（v2：后台刷新永不删行）+ 分段控件命中区域
- **Given** New 段打开，邮件 X 未读且在列表中
- **When** 任意**后台数据刷新**（markRead/markUnread、30s 轮询、历史回填批次、日期回补、手动同步）
- **Then** 列表成员**只增不删**：已在快照中的 X 留在原位（flags 原位合并——已读变轻但不消失）；新到达的未读邮件按 date 归位插入顶部；**被移出当前桶的行**（不在最新桶数据中，如 Set Aside/拦截/纠正移走）立即移除；其余一律不动
- **When** 用户**显式切换**分段或切换桶（或重新进入视图）
- **Then** 按最新 flags 全量重算（此时已读邮件归入 Previously seen）
- **And** 分段控件（New / Previously seen / Set aside）与阅读窗格胶囊按钮的点击命中区域为整个胶囊区域，而非文字笔画
- **Status**: green（v2 行为修订：v1 的"代际重算"把后台刷新也当重算触发，已读邮件被抽走——实测轮询/回填期间高发）
- **Tests**: `journey_018_segment_membership_stable_on_read`, `journey_018_merge_semantics_grow_only`

## JOURNEY-019 未读/已读行的字重编码
- **Given** 列表行 / 搜索结果行（视觉由 MailRowView 统一渲染）
- **When** isUnread == true / false
- **Then** 未读：发件人与主题走**粗体字重**且保留蓝色未读点；已读：发件人与主题走 regular 字重、无蓝点；字重映射由 RowEmphasis 纯函数提供（测试锁映射语义，视图零分叉）
- **Status**: green
- **Tests**: `journey_019_unread_bold_emphasis`

## JOURNEY-020 邮件时间戳贯穿（信封日期入库 → 列表/阅读窗格呈现）
- **Given** header-first 同步（FETCH UID FLAGS ENVELOPE，Date 头存在于 ENVELOPE[0]）
- **When** 引擎构造 MailEvent → apply 入库 → 列表/阅读窗格渲染
- **Then** ENVELOPE 的 Date 头透传至 MailEvent.date 并入库（**规范化为 ISO8601 使字符串排序=时间序**，解析失败保原文兜底；宽容解析 "…+0000 (UTC)" 类注释变体）；列表行时间与阅读窗格时间戳非空（解析支持 ISO 与存量 RFC2822 双格式）；多条邮件按收件时间倒序
- **And** 存量无日期邮件（断链时期入库）在 attach 后自动按 ENVELOPE 分批回填（仅补 date/信封字段，**不动 flags/raw**；完成后列表代际刷新，时间列出现）
- **Status**: green
- **Tests**: `journey_020_timestamp_pipeline`
