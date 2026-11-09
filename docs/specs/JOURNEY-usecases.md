# JOURNEY · 用户旅程与装配用例

## JOURNEY-001 骨架端到端装配（同步→镜像→分类→呈现）
- **Given** FakeImapServer 带 3 封邮件（roster 可命中 2 封 + 未知发件人 1 封），MailoAppModel.bootstrap
- **When** 同步引擎拉取 → 镜像入库 → 管线分类（名单库命中 + 模型低置信待定）→ 冻结 → 加载 bucket 列表
- **Then** imbox 列表含 roster 判定的邮件；低置信未知件计入 Screener 待定；全程零网络（进程内）
- **Status**: green
- **Tests**: `journey_001_bootstrap_end_to_end`

## DESIGN-001 Slate Concept 设计 token 与规范一致（v2.1）
- **Given** docs/design/design-system.md v2.1 的关键值
- **When** 读取 DesignTokens
- **Then** brand 蓝 #0078FF、五 bucket 语义色、三栏 ideal 172/388、选中细条 2pt、中性顶栏 64pt 与规范一致（防漂移）
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

## JOURNEY-004 HTML 邮件详情分离与沙箱渲染（v4：共享阅读色标且主题切换不重载）
- **Given** 一封 HTML-only 邮件（无 text/plain 部分），外观为 Light 或 Dark；邮件可为简单 HTML 或带作者排版标记的 HTML
- **When** mailDetail、沙箱 HTML 构建或主题切换
- **Then** textBody 为 nil、htmlBody 携带 HTML 原文；渲染层用 WKWebView + CSP（default-src 'none'; style-src 'unsafe-inline'; img-src data:）——远程图片默认禁，纯文本邮件仍走原生 Text
- **And** 简单 HTML 使用 reader 正文色标；含 style/class/bgcolor 等作者排版标记的邮件保留白色默认纸张底；CSS 色值来自同一 token，主题只经 media query 响应且不触发 reload；CSP/禁 JS/远程图片策略不变
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

## JOURNEY-008 三栏骨架原生化（v3：Slate Concept 连续表面）
- **Given** 已连接（或 demo）状态的三栏主界面，含选中 HTML 邮件
- **When** 渲染主壳或切换选中
- **Then** 骨架用 `NavigationSplitView`（侧栏可折叠 ⌘⇧C、分栏可拖动、窄屏自动单栏）；邮件列表用 `List(selection:)`——↑↓ 移动选中、↩ 在阅读窗格打开；不再有自绘红绿灯 spacer
- **And** 中性 toolbar 承载 Search、右侧账户/设置；Compose 位于侧栏；ideal 栏宽 172/388；选中接触阴影跨分栏但 detail 使用固定视口，头部与列表不因 HTML 内容尺寸偏移
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

## JOURNEY-014 正文异步加载（v3：持久头部、单一视口与过期提交防护）
- **Given** 正文未回填的邮件 X（raw 为空，需网络拉 BODY），并可快速连续切换选择
- **When** 打开 X / 切换到 X / 旧任务晚于新任务完成
- **Then** 加载由 onAppear + onChange(stableId) 显式驱动，Task 取消旧的；持久头部由 summary（含搜索结果）先渲染，正文后台拉取；失败重连重试后仍败显示错误与重试
- **And** 头部发件人/主题/时间恒显，无硬 Divider；HTML 只使用 reader 提供的有限视口，不上传无限/零高度；只有最新 stableId 可提交 loadState；正文就绪后才执行进入动画；期间 UI 可交互
- **Status**: green
- **Tests**: `journey_014_async_body_load`, `journey_014_html_content_height_capped`, `perf_005_latest_selection_wins`, `perf_005_detail_parse_off_main`

## JOURNEY-015 搜索防抖与取消
- **Given** 搜索框连续输入
- **When** 每次键入
- **Then** 250ms 防抖后才触发查询；新键入取消未完成的上一轮；Esc 清空搜索并恢复列表
- **Status**: green
- **Tests**: `journey_015_search_debounce`

## JOURNEY-016 Settings 场景（v2：⌘, + Appearance）
- **Given** 已连接应用，外观偏好为 System / Light / Dark 之一
- **When** 打开设置（⌘,）或修改 Appearance
- **Then** 提供账户页（邮箱、断开连接/重新连接）、隐私页（远程图片默认开关）、诊断页（schema 诊断、最近同步摘要）与 Appearance 选择；默认 System，选择本地持久化，并一致应用于主窗口、Compose、Settings 与 iOS sheet；断开连接清除本地凭证与账户记录并回到账户页
- **Status**: green
- **Tests**: `journey_016_settings_scene`, `design_005_appearance_preference`

## JOURNEY-017 手动纠正常驻入口（This isn't Imbox →）
- **Given** 阅读窗格打开桶 B 内邮件 X（发件人 sender@x.co）
- **When** 点「Not <B> →」选择目标桶 T
- **Then** 生成 senderExact→T 显式规则（CLS-006 语义）；X 与该发件人既有待定邮件全部移入 T；下一封同发件人直接进 T
- **Status**: green
- **Tests**: `journey_017_manual_correction_entry`

## DESIGN-002 Slate Concept token 全集与内联色清零（v2.1）
- **Given** 设计规范 v2.1 §2-§9 的完整 token 表（双主题排版/圆角/间距/阴影/状态色/控件状态/渐变色标）
- **When** 读取 DesignTokens
- **Then** 全部 token 有常量定义并被视图引用；视图层用户可见的颜色/字号零内联字面量；卡片/搜索/阅读宽度/渐变色标等新角色改走 token
- **Status**: green
- **Tests**: `design_002_full_token_set`

## DESIGN-003 多语言（默认英文 + 简体中文）
- **Given** String Catalog（Localizable.xcstrings）随 DesignKit 分发，开发语言 en
- **When** 系统语言为 en / zh-Hans / 其他
- **Then** en 与 zh-Hans 显示对应语言；其他语言回落英文；用户可见文案（含 Bucket 名、空态、按钮、错误）全部经 catalog 取出（零硬编码直出）；列表分段文案与规范一致（New / Previously seen / Set aside）
- **Status**: green
- **Tests**: `design_003_localization`

## DESIGN-004 Slate Concept 动效规范落地（v2.1）
- **Given** 规范 v2.1 §6/§9：微交互 120ms / 视图、主题与阅读转场 220ms / 归类 320ms spring(0.32, 0.86)
- **When** hover/pressed/focus、桶切换、搜索、分段、阅读选中、主题切换、Screener 决策或紧凑阅读导航
- **Then** 对应动效以 token 时长/曲线执行；阅读正文在**内容就绪后**以 opacity + 6pt 横移进入，持久头部不动；连接阴影使用固定几何 + opacity；「减弱动态效果」开启时无动画且无位移
- **Status**: green
- **Tests**: `design_004_motion_tokens`

## DESIGN-005 双主题解析、外观偏好与控件状态（v2.1：含阅读色标）
- **Given** Slate Concept v2.1 的语义色角色（含 reader/card 连接角色）、System/Light/Dark 外观偏好及共享控件状态
- **When** 分别以 Light/Dark 解析色板，或读取/持久化外观偏好，或解析 default/hover/pressed/focus/disabled 状态
- **Then** 每个语义角色返回规范指定的 light/dark hex；System 默认且 rawValue 可逆，选择可经 UserDefaults 跨会话恢复；控件状态只改变 token 化的表面/文字/边界/不透明度，禁用态不可交互
- **And** 主窗口、Compose、Settings 与 iOS sheet 使用同一 Appearance 入口，深浅色切换不改变任何邮件行为；动态色按角色复用
- **Status**: green
- **Tests**: `design_005_theme_palette`, `design_005_appearance_preference`, `design_005_control_states`

## DESIGN-006 阅读表面连续性与跨栏接触阴影（v2.1）
- **Given** Light/Dark、选中/未选中邮件，以及简单或作者排版的 HTML
- **When** 选中、切换、加载、失败或改变主题
- **Then** 选中卡片右/下接触阴影穿越列表/阅读区分缝，阅读区使用规范指定的连续色标；无蓝色连接块、无硬 Divider、无布局 morph
- **And** 持久头部在 summary/详情间保持稳定，正文列居中，空/加载/失败共用 ReaderSurface；作者排版 HTML 保留白色纸张；Reduce Motion 直接呈现最终表面
- **Status**: green
- **Tests**: `design_006_reader_surface_palette`, `design_006_connection_shadow_geometry`

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

## JOURNEY-021 连接自愈（正文加载与轮询）
- **Given** 已连接但传输已被服务器断开（ENOTCONN/closed）；reconnectHandler 已注入（真实账户）
- **When** 阅读窗格 loadDetail 拉取正文失败
- **Then** 经 ensureConnection 重连（refresh token → 新连接 → 换 runner.transport，**握手在后台线程**）并重试一次；成功则正常渲染；重连或重试仍失败才进 failed 态
- **And** 轮询遇传输失败同样静默自愈（重建连接，下轮恢复；MAIL-025「失败不降级 UI」语义不变）
- **Status**: green
- **Tests**: `journey_021_body_load_reconnects`

## JOURNEY-022 删除邮件（移到 Trash）
- **Given** 已装配会话（列表含邮件 X，服务器 INBOX 同步持有）
- **When** 用户触发删除（阅读窗格菜单 / 列表右键 / 消息菜单 ⌫）
- **Then** 本地行删除（列表即刻消失、桶计数消减）；选中移到相邻邮件（无相邻则清空回占位）；服务器 UID MOVE 写回在后台尽力而为（成功则 INBOX 消失、Trash 出现；失败不回滚本地，仅诊断提示）
- **And** 命令面：MailoUICommand.delete 经壳层 handle 消费；菜单可用性要求「有选中且处于阅读态」（与 Reply/Forward 同矩阵）
- **Status**: green
- **Tests**: `journey_022_delete_moves_to_trash`, `journey_022_delete_command_routing`

## JOURNEY-023 正文加载独立通道（不与同步连接竞争）
- **Given** 已装配会话且注入 bodyTransportFactory（生产：独立 XOAUTH2 连接；未注入回落主连接——demo/测试）
- **When** 阅读窗格拉取无正文邮件（loadDetail → fetchBody）
- **Then** 走独立通道的传输，不占用同步连接的命令锁（回填批/轮询不阻塞点开正文）；独立通道被踢则废弃并在下次拉取重建；主连接自愈（JOURNEY-021）语义保留
- **Status**: green
- **Tests**: `journey_023_body_load_uses_dedicated_channel`
