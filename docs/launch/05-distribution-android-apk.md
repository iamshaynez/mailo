# 05 · Android 分发：apk 直发（不上架商店）

> 决策背景：安卓不上架任何商店，官网/CDN 直发 apk。
> 这砍掉了 Google Play 的 $25 注册、审核、政策约束，但把三件事揽回自己手里：
> **签名密钥自管（生死级）、更新机制自建、以及一个必须知情的 App 备案义务（§6）**。
> 本文档同时是安卓端工程约束清单（GMS 零依赖，§5）。

## 1. 分发通道

- 下载页：静态站点（与隐私政策同源部署，见 04 文档），提供 apk 直链 + 版本号 + SHA-256
- apk 文件：静态 CDN（与名单库/模型同一套 CDN，无用户数据、零合规负担）
- 渠道包不做；单一通用 apk（无商店渠道号需求）

## 2. 签名密钥管理（直发模式下这是最高风险项）

**直发 apk 没有 Play 的密钥轮换机制：上传密钥丢失 = 该包名永久无法更新，只能换包名从零开始。**

1. 生成上传 keystore：`keytool -genkey -v -keystore mailo-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias mailo`
2. 使用 **v2 + v3 签名**（`apksigner`，Android 7+ 全覆盖；v1 兼容按 minSdk 决定）
3. 密钥保护：
   - keystore + 密码分两处保存（公司保险库 / 另一位创始人）
   - CI 打签名包时通过 secrets 注入，**绝不入库**（.gitignore 已覆盖 *.jks/*.keystore，见仓库根）
4. 备份演练：从备份恢复 keystore 并验证签名一次，才算备份成立

## 3. 更新机制（自建，零后端方案）

1. CDN 放 `manifest.json`：`{versionCode, versionName, apkUrl, sha256, minOs, notesUrl}`
2. 客户端策略：启动 + 每 24h 拉一次 manifest（与名单库热更同一机制，复用同一组件）
3. 比对 `versionCode` → 提示更新 → 下载到应用沙箱 → 校验 SHA-256 → 拉起系统安装器
4. 权限：`REQUEST_INSTALL_PACKAGES`（Android 8+ 需用户在设置里确认"允许安装未知应用"）；首次安装的用户引导文案要提前写好
5. 失败兜底：校验不过拒绝安装并提示手动下载（下载页常驻直链）

## 4. 构建与加固

- R8 混淆 + 资源压缩默认开启；崩溃符号表（mapping.txt）随版本归档（对应版本留存，否则线上崩溃不可解析）
- 版本归档规范：每个发布的 apk + manifest.json + mapping.txt 三件套入版本目录（CDN + 本地双存）
- ABI 拆分或 universal apk 按体积决策（embedding 模型不打包、首启下载，apk 本体可控制在几十 MB）

## 5. GMS 零依赖约束（大陆无 Google 服务设备的硬要求）

安卓端**禁止引入任何依赖 Google Play Services 的库**：

| 功能 | 无 GMS 方案 | 状态 |
|---|---|---|
| Gmail OAuth | AppAuth（Custom Tab / 外部浏览器 + 自定义 scheme 回跳），**不用 Google Sign-In SDK** | 二期实现时验证 |
| Microsoft 登录 | MSAL Android 本身不依赖 GMS ✓ | — |
| 推送 | 本方案无推送：前台服务保 IMAP IDLE（见基线 D7） | — |
| 地图/支付等 | 不涉及 | — |

无 Chrome 的设备上 Custom Tab 会退化到外部浏览器流程——AppAuth 已处理，e2e 要覆盖这条退化路径。

## 6. ⚠️ App 备案义务（必须知情后做决策）

2023 年工信部《关于开展移动互联网应用程序备案工作的通知》：**面向中国大陆提供服务的 app（包括官网直发 apk 形态）应完成 App 备案**。不备案的合规风险由运营方承担。

两条路径，二选一并写回本节：

| 路径 | 内容 | 成本 |
|---|---|---|
| **A（默认建议）**：首版仅面向海外分发 | 下载页英文/海外 CDN、不做大陆推广 | 零额外成本；大陆用户自行下载属灰色地带，风险自担且普遍 |
| **B：面向大陆正式分发** | 公司先完成 ICP 网站备案（需一台大陆服务器 + 域名接入，约 2-6 周）→ 云服务商备案控制台提交 App 备案（填包名、签名、下载页等） | 新增大陸服务器年费 + 备案流程；服务器仅承载下载页/备案主体，**不承载用户数据，零后端原则不破** |

> 决策记录：（待定。若选 B，同步修订 01 文档 §3——iOS 上中国区可复用同一备案主体。）

## 7. 时机

Android 二期（M2 后启动，见基线路线图）。本文档的 §2 密钥管理可在 M0 提前完成（生成 + 入库备份流程演练），因为它是纯运维动作且是最高风险项。

## 完成标志（DoD，二期验收用）

- [ ] keystore 生成、双备份、恢复演练通过
- [ ] 下载页 + manifest 更新链路全通（含 SHA-256 校验拒绝路径）
- [ ] 无 GMS 设备（或禁用 Play 服务模拟）上 Gmail OAuth 退化流程 e2e 通过
- [ ] §6 备案决策已记录

## 参考

- [Android 应用签名官方文档](https://developer.android.com/studio/publish/app-signing)
- [AppAuth（OpenID）Android](https://github.com/openid/AppAuth-Android)
- 工信部 App 备案：经云服务商（阿里云/腾讯云）备案控制台提交
