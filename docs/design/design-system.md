# Mailo 设计规范 · Blue Box Classic（v1）

> 决策日期：2026-11-07。三方案（A Blue Box Classic / B Midnight Statement / C Calm Paper）中选定 **A**。
> mockup 归档：`mockups/mailo-style-a-bluebox.html`（**视觉基线**，像素级参照物）；
> B/C 保留于同目录作存档（B 的深色语言列为 M3 后 dark mode 候选，C 弃用）。
> 本规范是 M1 UI 实现的 token 来源，SwiftUI 色板/字体/间距以此为准。

## 1. 设计原则

1. **运通蓝即身份**：`#006FCF` 承载一切品牌感——标题栏、选中态、主按钮、未读点。蓝不滥用：界面中蓝色出现的地方 = 可交互或需注意。
2. **白底卡片、规整克制**：金融服务级的信任感；阴影轻、边框细、圆角中等。不追玻璃拟态/辉光等潮流。
3. **隐私卖点可视化**：常驻 "● 100% on-device" 徽章 + Screener 顶条——产品理念必须长在界面上。
4. **hey 式信息架构**：三栏（导航 / 列表 / 阅读）；列表三段（New / Previously seen / Set aside）；邮件行的类别一目了然。

## 2. 色板（SwiftUI Color Asset 命名）

### 品牌与语义
| Token | Hex | 用途 |
|---|---|---|
| `brand/blue` | `#006FCF` | 主品牌（运通蓝）：标题栏、选中、主按钮、未读点、链接 |
| `brand/blueDeep` | `#0B4E96` | 深蓝：banner 强调文字 |
| `brand/blueWash` | `#E8F1FB` | 浅蓝底：选中行、徽章底、hover |
| `brand/blueBorder` | `#CFE2F6` | banner 边框 |

### 中性
| Token | Hex | 用途 |
|---|---|---|
| `ink/primary` | `#16202F` | 主文字（发件人、标题） |
| `ink/secondary` | `#3C4657` | 次文字 |
| `ink/muted` | `#8892A6` | 预览行、时间 |
| `ink/faint` | `#9AA4B5` | 分组标签、辅助 |
| `surface/main` | `#FFFFFF` | 列表/阅读面板底 |
| `surface/subtle` | `#F1F4F9` | 分段控件底、hover |
| `surface/wash` | `#F7FAFE` | 行 hover（偏蓝） |
| `border/default` | `#E8ECF3` | 分栏、行分隔 |
| `border/hairline` | `#F1F4F8` | 行内细分隔 |

### 分类语义色（hey 式 bucket 的视觉身份，贯穿导航点/徽章/头像描边）
| Token | Hex | 对象 |
|---|---|---|
| `bucket/imbox` | `#006FCF` 蓝 | 真人要信 |
| `bucket/feed` | `#E8710A` 橙 | 订阅要翻 |
| `bucket/paper` | `#64748B` 灰蓝 | 凭据要存 |
| `bucket/screener` | `#7C3AED` 紫 | 陌生要审 |
| `bucket/aside` | `#C4A35A` 金 | 事要缓办 |

### 状态
| Token | Hex | 用途 |
|---|---|---|
| `status/successBg` / `status/successFg` | `#F0F7EE` / `#2E7D32` | on-device 徽章 |

## 3. 排版（系统栈，不自带字体文件）

`-apple-system / SF Pro`；**不打包自定义字体**（包体与本地化负担为零）。

| 阶梯 | size/weight | 用途 |
|---|---|---|
| Title | 22 / 800 / -0.3 tracking | 阅读页主题 |
| Head | 19 / 800 | 列表标题（Imbox） |
| Sub | 16 / 800 | 阅读页发件人 |
| Body-strong | 13.5 / 700 | 列表发件人、导航项(500) |
| Body | 14 / 400 / 1.75 行高 | 邮件正文 |
| Caption | 12.5 / 600 | 列表主题、按钮 |
| Meta | 11.5 / 500 | 预览行 |
| Micro | 10.5 / 700 / +1.2 tracking 大写 | 分组标签（TODAY）、bucket lab |

## 4. 布局与形状

- 三栏：**212 / 392 / flex(≥600)**；标题栏 52；行高约 72（头像 36）
- 圆角：窗 14 / 面板内卡片·头像 10 / 按钮·徽章 8 / pill 999
- 选中态：`brand/blueWash` 底 + **3px 左侧 inset 蓝条**（签名元素）
- 间距节奏：栏内 16，面板内 20-30，阅读区左右 30
- 阴影：仅窗口与主按钮（`0 4px 14px rgba(0,111,207,.35)`），行与卡片不加影

## 5. 关键组件规约

- **Screener 顶条**：`blueWash` 底 + 蓝点 + 深蓝文案 + 右侧 "Review →"；空状态时整个隐藏（不打扰）
- **分段控件**：胶囊三段（New / Previously seen / Set aside），激活白底浮起+蓝字
- **邮件行**：头像(36, 10 圆角) / 发件人+未读点+时间 / 主题 / 预览；bucket 用头像底色暗示，不加行内徽章（保密度，列表保持安静）
- **阅读页 bucket 卡**：右上 `IMBOX` Micro 标签 + "Real person ✓"
- **主按钮**：蓝底白字 `Reply ↩`；次级白底灰边；危险操作永远在 ⋯ 菜单里
- **on-device 徽章**：常驻侧栏底部，成功色

## 6. 动效规范（对应基线 §7 的 jank 门禁）

- 时长：微交互 120ms / 视图转场 220ms / bucket 归类动画 320ms（邮件"飞入" Feed 时用 bucket 色轨迹）
- 曲线：默认 `easeOut`；归类动画 `spring(response:0.32, dampingFraction:0.86)`
- 原则：动画只用于**表达归类语义**（邮件去哪了），禁止装饰性动画

## 7. 深色模式

**第一期不做**（M1-M3 锁 light，保证一门心思打穿）。dark 起点参考 mockup B 的 `#0A1220` 系，M3 后作为 v2 规范再立。

## 8. UX 流程要点（UI 稿之外的行为约定）

- **⌘K 命令面板**是第一公民：搜索、切换 bucket、归类动作全部可键盘直达
- Screener 决策三键：Allow to Imbox / Allow to Feed / Block——批准即生成显式规则（对应基线 D8 管线①）
- 手动纠正的入口常驻阅读页（"This isn't Imbox →"），纠正即出规则，永不静默学习
- 双端差异：macOS 三栏常驻；iOS 列表/阅读推拉切换 + 底部 bucket 栏（A 风格在小屏的等价表达，M1 出 iOS 版 mockup 再审）
