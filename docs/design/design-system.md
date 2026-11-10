# Mailo 设计规范 · Inbox Reference Exact + Amex Blue（v4.3）

> v4.3（2026-11-10）：主邮件窗口固定为原图浅色，不再因保存的 Dark 偏好把邮件列表变成深灰；Compose/Settings 仍尊重用户外观偏好。
> 原图：`mockups/inbox-concept/app-window.png`（898 × 640）。营销背景、标题和系统窗口 chrome 不属于组件画布。
> 视觉优先级：几何与层级 > 原生默认样式。现有邮件、分类、命令、安全能力通过 More、右键、快捷键与设置保留。

## 1. Amex Blue 外观与色板

- 主邮件窗口固定为 **Light**，不跟随 Dark 偏好；Compose/Settings 仍尊重 System/Light/Dark。主行动与美国运通蓝一致：`#0077C8`。
- 侧栏改为深海军蓝 `#071C2C`，选中导航 `#123A52`；文字 `#F3F8FC`，次文字 `#8BA8BC`，不再使用墨绿。
- 普通列表行、搜索栏与阅读纸面均为 `#FFFFFF`；hairline `#E8EEF2`。选中行通过白色表面与阴影抬升，不使用灰色卡片底色。
- accent 用于 Mail 左条、未读点、计数、focus、附件强调和 Send；按钮文字保持白色。
- 中性文字/边界改带蓝色灰阶：primary `#14232E`，secondary `#4B5F6E`，body `#2C3E4B`，muted `#7E919E`，faint `#A1AEB8`。
- Dark 使用蓝色灰阶：toolbar `#111E28`、list `#15232D`、card `#1F303C`、reader `#1B2A35`；正文 `#D4E0E7`，次文字 `#B6C6D1`，控件 `#253743`，边界 `#31444F`。
- accent deep/wash/border 分别为 `#005A9C` / `#E9F4FC` / `#B8DDF3`。分类与成功状态保留语义色。
- Logo 恢复上一版的 **m + 圆点**，由侧栏和欢迎页共用；圆点与主 accent 一致，不使用多色 M。

## 2. 精确几何

### 三栏

- 898 画布：侧栏 139 / 列表 345 / 阅读 414。
- 比例：**15.48% / 38.42% / 46.10%**。
- 1280 默认窗口：约 198 / 492 / 590；960 最小窗口：约 149 / 369 / 442。
- regular 宽度使用受控 HStack 几何，不让 NavigationSplitView `.balanced` 重新分配比例；compact 保持列表—阅读导航。

### 侧栏

- m + 圆点 Logo 居中，顶部 20、底部 16；不带 Mailo 字标。
- 导航行高 34，左右图标/文字间距 10；选中为全宽矩形 + 左侧 3pt 绿条，无胶囊。
- 顺序严格为 Mail / Chat / Spaces / Call / Compose，然后 Inbox / Starred / Snoozed / Sent / Draft / More，再是 Labels +。
- 不显示账户卡片、隐私页脚或绿色 Compose 大按钮。未开放模块保持视觉槽位但不执行假动作；真实桶、筛选、设置与退出 Demo 收进 More。

### 列表

- 搜索栏高 42，白色、无独立胶囊描边；左侧放大镜，placeholder「Search for message…」。不显示筛选图标。
- 邮件行高 98，全宽，无卡片圆角、左右缩进或选中左条；普通/选中行均为白色，底部 0.5 hairline。
- 原图层次必须保留：搜索行 shadow 6/y3/opacity 0.06；普通行 shadow 6/y3/opacity 0.06；选中行 shadow 14/y4/opacity 0.12；列表右缘向阅读区投影 12/x4/opacity 0.10。阴影不拦截点击、不改变布局尺寸。
- 头像 26；内容顺序为「发件人＋时间＋未读点 → 主题 → 最多两行摘要」。未读粗体+绿点，已读 regular。
- 默认 **All**，已读与未读混合展示；New / Previously seen / Set aside 在 More 中可选。

### 阅读区

- 内容左缘 20、右缘约 44；最大阅读宽度 600。
- 头部：头像 26，发件人＋to＋收件人一行；日期在下一行；无动作图标组、桶徽章或额外地址卡片。
- 主题 20/600，距头部 14；正文 14/400、1.65 行高。加载/失败仍保留 summary 头部。
- 图片附件：三张 104×100、间距 12、圆角 8；真实 MIME 图片，非图片用类型占位；更多只显示 +N。
- 快速回复输入卡高 60，聚焦/错误时扩展；**Send 是输入卡外右下方的独立胶囊按钮**，不与输入框挤在同一行。
- Demo/Screener 不在主画布上方增加横幅。Demo 由原生窗口标题标识；Screener 决策只在对应邮件上下文出现。

## 3. 排版

继续使用 SF Pro：Title 20/600；Head 16/600；Sub 15/600；Body-strong 13/600；Nav 12.5/500；Body 14/400；Caption 12/600；Meta 11/400；Micro 9.5/600。参考图缩小的 7–10px 字形不直接用于生产可读字号。

## 4. 动效与 UX

- hover/pressed/focus 120ms easeOut；视图/阅读/回复 220ms easeOut；归类 320ms spring(0.32,0.86)。
- 选中只改变表面，不改变行高或栏宽；正文就绪后 opacity + 6pt 位移；持久头部不动。
- 回复框聚焦只扩展输入卡，Send 保持在右下；发送中、失败、成功状态均不清空其他邮件草稿。
- Reduce Motion 取消动画和位移；所有新文案有 en/zh-Hans；未开放槽位有无障碍说明。

## 5. 不变的行为边界

- 保留搜索 250ms、Esc、邮件选择、删除相邻回退、Set Aside/undo、Screener、纠正、同步与正文独立通道。
- Reply/⌘R 聚焦快速回复；展开复用完整 Compose；真实账户发送走既有 SMTP，Demo 不模拟成功。
- HTML CSP、禁 JS、远程图片默认关闭、作者样式保护、主题切换不重载不变。
- 新邮件无正文缓存时必须取得真实正文；服务器空响应不得伪装为 loaded 的 `(no body preview)`。
- 不新增真实 Chat/Call/Starred 数据模型；这些参考图槽位不执行未授权动作。
