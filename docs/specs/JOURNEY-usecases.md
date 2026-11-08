# JOURNEY · 用户旅程与装配用例

## JOURNEY-001 骨架端到端装配（同步→镜像→分类→呈现）
- **Given** FakeImapServer 带 3 封邮件（roster 可命中 2 封 + 未知发件人 1 封），MailoAppModel.bootstrap
- **When** 同步引擎拉取 → 镜像入库 → 管线分类（名单库命中 + 模型低置信待定）→ 冻结 → 加载 bucket 列表
- **Then** imbox 列表含 roster 判定的邮件；低置信未知件计入 Screener 待定；全程零网络（进程内）
- **Status**: draft
- **Tests**: `journey_001_bootstrap_end_to_end`

## DESIGN-001 设计 token 与规范一致
- **Given** docs/design/design-system.md 的关键值
- **When** 读取 DesignTokens
- **Then** brand 蓝 #006FCF、五 bucket 语义色、三栏宽 212/392、选中蓝条 3pt 与规范一致（防漂移）
- **Status**: draft
- **Tests**: `design_001_tokens_match_spec`

## JOURNEY-002 真实账户装配路径（注入传输）
- **Given** AppModel.connect(account:transport:) 以 FakeImapServer 为注入传输（CI 可测，生产注入 TcpImapTransport）
- **When** 走完整装配：设备码授权（生产）→ 连接 → 同步 → 入库 → RosterSeed 分类 → 冻结 → 列表
- **Then** feed/paperTrail/imbox 各桶正确呈现；未知发件人低置信进 Screener 计数；本地库为文件路径模式（跨启动持久）
- **Status**: draft
- **Tests**: `journey_002_real_account_assembly`

## JOURNEY-003 邮件详情与未读呈现
- **Given** 已入库邮件（含完整 raw 字节）
- **When** mailDetail(stableId) 与列表渲染
- **Then** 详情含完整正文（从 raw 重新解析，非 200 字 snippet）；未读判定 = flags 不含 \\Seen（列表"New"分段依据）
- **Status**: draft
- **Tests**: `journey_003_detail_and_unread`

## JOURNEY-004 HTML 邮件详情分离与沙箱渲染
- **Given** 一封 HTML-only 邮件（无 text/plain 部分）
- **When** mailDetail
- **Then** textBody 为 nil、htmlBody 携带 HTML 原文；渲染层用 WKWebView + CSP（default-src 'none'; style-src 'unsafe-inline'; img-src data:）——远程图片默认禁（规范 §7），纯文本邮件仍走原生 Text
- **Status**: draft
- **Tests**: `journey_004_html_detail_separated`
