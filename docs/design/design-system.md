# Mailo 设计规范 · Slate Concept（v2.1）

> v2.1（2026-11-08）：第二轮逐像素审计补齐跨栏接触阴影、阅读区连续渐变、持久头部与渲染性能约束。

> 决策日期：2026-11-08。用户提供的新概念稿取代 **A / Blue Box Classic** 成为视觉基线。
> 原始参照：`mockups/slate-concept/source.png`（1024 × 768；应用窗口约 905 × 593）。
> 旧 A/B/C HTML 仅作历史归档，不再约束当前 UI。本文是 DesignKit 的 token、组件与动效来源。
> 深色直接从原稿采样；浅色与动效是同一视觉语言的补全，不是对原稿的机械反色。

## 1. 设计原则

1. **明暗分层代替重边框**：侧栏/顶栏最深，列表次之，卡片再亮一级，阅读区拥有独立表面。
2. **悬浮邮件卡片**：列表不是密集表格；卡片有独立圆角、留白和轻微选中 elevation。
3. **蓝色只给主行动与未读**：主按钮、focus、未读点使用 `#0078FF`；普通导航选中不靠整块蓝底。
4. **阅读优先**：约 520pt 正文测量宽度、居中留白、清晰层级；工具图标安静，命中区域不随 glyph 缩小。
5. **隐私与归类语义保留**：on-device 徽章、Screener、hey 式 bucket 仍是 Mailo 产品身份，不照抄概念稿的虚假标签。
6. **双端同源**：macOS/iPad 三栏；iPhone 使用同一 token 的紧凑列表/阅读导航，不把桌面比例硬缩。

## 2. 双主题色板

颜色由 `DesignTokens.ThemeColor` 的 light/dark 原始 hex 锁定，再派生动态 SwiftUI Color。

### 表面

| Token | Light | Dark（原稿采样） | 用途 |
|---|---|---|---|
| `surface/sidebar` | `#E9EDF3` | `#171D22` | 侧栏 |
| `surface/toolbar` | `#E9EDF3` | `#171D22` | 中性顶栏 |
| `surface/list` | `#F3F5F8` | `#171D24` | 列表栏 |
| `surface/card` | `#FFFFFF` | `#242933` | 邮件卡片 |
| `surface/cardSelected` | `#FFFFFF` | `#2B323D` | 选中卡片 |
| `surface/reader` | `#FFFFFF` | `#3C4350` | 阅读表面中点（不再单独铺平） |
| `reader/leading` | `#FAFCFF` | `#3B434F` | 阅读区前缘/跨栏连接终点 |
| `reader/header` | `#FFFFFF` | `#3A424D` | 阅读头部上左色标 |
| `reader/bodyTop` | `#FCFDFF` | `#3D4551` | 正文上部色标 |
| `reader/bodyBottom` | `#F6F8FB` | `#343C47` | 正文下部色标 |
| `reader/trailing` | `#F3F5F9` | `#38404B` | 阅读区右下色标 |
| `reader/chip` | `#F0F3F7` | `#47505C` | 阅读区内附件 chip（比父表面略亮） |
| `card/selectedBorder` | `#D8DEE7` | `#39424D` | 选中卡片低对比 tonal edge |
| `surface/control` | `#E7ECF2` | `#2B3442` | 分段底、次级控件 |
| `surface/hover` | `#EDF1F6` | `#2B323E` | hover/pressed |
| `surface/search` | `#FFFFFF` | `#F6FAFF` | 概念稿标志性亮搜索框 |

### 文字、边界与品牌

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `ink/primary` | `#18202B` | `#F4F6FA` | 标题、发件人 |
| `ink/secondary` | `#4B5665` | `#B2BAC7` | 次文字 |
| `ink/body` | `#283444` | `#D5DAE3` | 正文 |
| `ink/muted` | `#7A8594` | `#8791A1` | 摘要、时间 |
| `ink/faint` | `#9AA4B1` | `#606B7B` | 分组、辅助 |
| `border/default` | `#DDE3EB` | `#303845` | 控件/面板边界 |
| `border/hairline` | `#E9EEF4` | `#262D38` | 极细分隔 |
| `border/strong` | `#C9D2DE` | `#4A5565` | focus 前可见边界 |
| `brand/blue` | `#0078FF` | `#0078FF` | 主按钮、未读、focus |
| `brand/blueDeep` | `#0B4E96` | `#75B9FF` | banner 强调文字 |
| `brand/blueWash` | `#E8F2FF` | `#1D3550` | 选中/徽章弱底 |
| `brand/blueBorder` | `#C8E0FA` | `#2E537A` | banner 边界 |
| `status/successBg` | `#E7F5EC` | `#17372B` | on-device 底 |
| `status/successFg` | `#237A46` | `#4BCD8B` | on-device 文案 |
| `status/danger` | `#D94452` | `#FF6B74` | 错误/破坏性操作 |

### 分类语义色

| Token | Hex | 对象 |
|---|---|---|
| `bucket/imbox` | `#0078FF` | 真人要信 |
| `bucket/feed` | `#E8710A` | 订阅要翻 |
| `bucket/paper` | `#64748B` | 凭据要存 |
| `bucket/screener` | `#9561D9` | 陌生要审 |
| `bucket/aside` | `#C4A35A` | 事要缓办 |
| `bucket/blocked` | `#8892A6` | 已拦截 |

## 3. 排版

继续使用系统 SF Pro，不打包字体。原图是缩小的营销画布，7–8px 字形不能直接作为生产字号；按窗口比例和可读性换算。

| 阶梯 | size/weight | 用途 |
|---|---|---|
| Title | 20 / 600 | 阅读页主题 |
| Head | 16 / 600 | 列表桶名 |
| Sub | 15 / 600 | 阅读页发件人 |
| Body-strong | 13 / 600 | 卡片主题、强调发件人 |
| Nav | 13 / 500 | 导航项 |
| Body | 14 / 400，1.7 行高 | 邮件正文 |
| Caption | 12 / 600 | 按钮、分段 |
| Meta | 11 / 400 | 摘要、时间 |
| Micro | 9.5 / 600，+1.1 tracking | 大写分组 |

## 4. 布局、形状与阴影

以 1280pt 宽窗口对原图 905px 应用窗口做比例换算，同时保留系统 resize：

- 三栏 ideal：**172 / 388 / flexible**；侧栏 min 160/max 240，列表 min 340/max 520。
- 中性顶栏 64；搜索框 ideal 374 × 32，最大 440。
- 邮件卡片实际内容 min height 82 + 上下间距；头像 22，阅读头像 36。选中不改变布局尺寸。
- 阅读正文 max 520，**居中**；头部外框 max 576，使头像向正文左 gutter 伸出；sender/附件/主题与正文左缘对齐。
- 阅读区右侧保留 20pt、底部保留 16pt 的窗口 gutter；滚动条 2–3pt、透明轨道。
- 圆角：window 14 / card 7 / button 8 / search 6 / media 10 / primary capsule。
- 选中导航使用 2pt 细条；卡片选中使用 `cardSelected` + `card/selectedBorder`，不再使用整块蓝底。
- **跨栏连接**：选中卡片右/下接触阴影（x≈3、y≈4、blur 8）由主壳合成穿越列表/阅读区分缝；无箭头、无蓝色连接块、无布局 morph。
- **阅读渐变**：`header → bodyTop → bodyBottom/trailing` 的上左亮、下右暗连续多 stop 表面；头部与正文间没有硬 Divider。
- 阴影使用固定 blur/offset + opacity 过渡；不得添加玻璃拟态、循环 glow 或大面积彩色投影。

## 5. 组件规约

- **顶栏**：中性表面；搜索位于列表上方，账户状态/设置入口位于右侧；Compose 移到侧栏。
- **侧栏**：Mailo 标识、蓝色胶囊 New Message、小色标导航、常驻隐私页脚。选中项亮文字 + 细条。
- **列表工具行**：当前 bucket + 数量；现有分段 New / Previously seen / Set aside 保留，以浮起选择块滑动。
- **邮件卡片**：主题、最多两行摘要、底部圆形头像/发件人/时间；未读保留粗字与蓝点，已读 regular。
- **阅读头部**：单一持久头部，头像/发件人/时间 + Reply/Forward/Set Aside/纠正菜单；加载/失败也由 summary 保持，不再“操作条 + meta”双层重复。无硬分割线。
- **附件**：已有文件名渲染被动 chip，flow 换行；`reader/chip` 比父表面略亮，无重描边；不伪造预览/下载动作。
- **按钮**：primary 蓝底白字；secondary 有低对比底与边界；ghost/icon 默认无容器，hover 才浮起；disabled 降低不透明度且不可点。
- **辅助页面**：Compose、Settings、账户向导、搜索、空态、加载/失败、Demo/Screener 顶条使用同一 token。
- **HTML 邮件**：简单 HTML 的默认背景/正文/链接与 `color-scheme` 随主题；含 style/class/bgcolor 等作者排版标记的邮件保留白色默认纸张底，避免显式深字在暗底上失读。尊重作者显式样式，不做颜色反转；CSP 与远程图片策略不变。

## 6. 动效规范

| 场景 | 时长/曲线 | 表现 |
|---|---|---|
| hover / pressed / focus / 卡片选中 | 120ms easeOut | 轻微亮度、表面或 0.98 按压缩放 |
| bucket / 搜索 / 主题切换 | 220ms easeOut | 交叉淡化，不整体飞屏 |
| 阅读邮件切换 | 220ms easeOut | **内容就绪后** opacity + 6pt 横移；头部不位移 |
| 分段选择 | 220ms easeOut | `matchedGeometryEffect` 选择块滑动 |
| iPhone 阅读页 | 220ms easeOut | trailing push；返回反向 |
| 分类/移出列表 | 320ms spring(0.32, 0.86) | 保留归类语义动画 |

- 「减弱动态效果」开启：取消动画与位移，直接呈现最终状态。
- 动画用于表达状态与空间关系；禁止循环、辉光、视差等装饰性动画。

## 7. 外观设置

Settings 新增 Appearance：System（默认）/ Light / Dark，使用 `@AppStorage` 持久化。主窗口、Compose、Settings 和 iOS sheet 一致应用；动态颜色在未覆盖时跟随系统。

## 8. 不变的产品行为

- `NavigationSplitView`、`List(selection:)`、侧栏折叠、键盘导航和现有快捷键不变。
- Reply/Forward 预填、Set Aside/undo、Screener 决策、手动纠正、搜索 250ms 防抖、Esc 清空不变。
- 阅读加载/失败/重试、头部布局、时间戳、未读/已读字重与后台刷新段成员稳定不变。
- 本批次只做视觉与动效：不新增多选、Filter、Delete all、全部已读、自定义标签、附件预览等工作流。

## 9. 渲染与响应约束（v2.1）

- 相同 HTML + 远程图片策略：WebView 不重载；主题切换只由 CSS media query 响应。
- 正文视口只从 reader 容器取得，不再并行读取 window 高度；禁止无限/零高度上传。
- 选择邮件时卡片反馈优先；网络与 MIME 解析不占主线程；过期详情不得提交。
- flags-only 更新只原位改字重/未读点，不重建日期索引、不排序、不触发分类 spring。
- 阴影和 focus 动画使用固定几何 + opacity；动态色按角色复用。
