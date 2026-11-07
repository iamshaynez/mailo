# 01 · Apple Developer Program 注册（组织主体）

> 目的：App Store 上架、TestFlight 内测、推送/证书/CI 打包的入口。
> 为什么 M0 第一天启动：D-U-N-S 签发最长 2 周 + Apple 核实约 5 个工作日，
> 而 CI 真机打包、TestFlight 全都卡在它后面。
> 信息查证时间：2026-11，以 Apple 官方帮助页为准。

## 0. 前置决策（注册前必须定死）

1. **主体类型**：组织 vs 个人
   - 组织：App Store 显示公司名、可加团队成员、可信度高 —— **推荐**
   - 个人（$99 同价）：上架显示个人法定姓名，对邮件客户端这类高信任品类是减分项
2. **公司实体是否已注册**：Apple 会向 D&B（邓白氏）核实你的法人实体。公司还没注册的话，先去办公司，再回来。
3. **Bundle id 定死**（如 `com.<公司域名>.mailo`），后面 Google/Microsoft 注册都用它，改起来极痛。

## 1. 申请 D-U-N-S 编号（免费，最长的等待项）

1. 打开 [D-U-N-S 查询页](https://developer.apple.com/D-U-N-S/)（Apple 的 lookup 工具）
2. 用公司法定英文名/地址查重 —— **常常已经存在**（公司注册、银行开户时可能已生成），先查再申请
3. 查无 → 同页面提交申请，需要：
   - 法定实体名（英文，与营业执照翻译一致）
   - 总部地址、电话
   - 联系人（你本人即可）
4. 等待签发：官方说法最长 ~2 周，签发后还要几天才同步进 Apple 系统

**坑**：实体名/地址与 D&B 记录**逐字一致**（包括标点、缩写、大小写）是后面 Apple 核实通过的关键。信息有误要先在 D&B 侧更正（又 1-2 周）。D&B 可能打电话核实，接听并如实回答可加速。

## 2. 注册管理用 Apple ID

1. 用**公司专属邮箱**（如 `apple-dev@公司域名`，不要用个人邮箱）注册一个新 Apple ID：https://appleid.apple.com
2. 开启双重认证，记下恢复方式
3. 这个 Apple ID 将成为团队 Account Holder —— 应由创始人/有权签字人持有

## 3. 组织注册

1. 打开 https://developer.apple.com/programs/enroll/
2. 用上面的 Apple ID 登录，选 **Company / Organization**
3. 填写：
   - 实体类型、法定实体名（同 D&B 记录）
   - D-U-N-S 编号
   - 总部地址、电话、公司网站（网站要能访问，内容与公司业务对得上）
   - **法务联系人（Legal Contact）**：有权代表公司签合同的职位与电话
4. 同意协议，在线支付 **$99/年**
5. Apple 电话核实（几天内）：通常打给法务联系人，确认"是否授权 XX 注册开发者账号" —— 提前打招呼，别漏接

## 4. 激活后立即做的 5 件事（工程侧联动）

1. 记录 **Team ID**（Member Center 首页可见）—— CI 配置要用
2. Certificates, Identifiers & Profiles → Identifiers → 注册 App ID（bundle id）→ 开启需要的 capability（首版：无特殊 entitlement；不做默认邮件客户端，避免 Mail entitlement 审核）
3. 生成 **Apple Development** + **Apple Distribution** 证书；私钥进公司保险库（丢失只能吊销重来）
4. App Store Connect：创建 App 记录（名称、bundle id、SKU），App Privacy 里按 04 文档填 **"Data Not Collected"**
5. 日历记两个日期：**年费续费日**、团队 Account Holder 变更流程（人员离开时）

## 完成标志（DoD）

- [ ] Membership 状态 Active，App Store Connect 能建 App 记录
- [ ] 能从 CI 打出带 distribution 签名的包（TestFlight 可装）
- [ ] Team ID / 证书 / bundle id 三件套已写进项目 `docs/launch/secrets-location.md`（只记位置，不记密钥本身）

## 卡住时的降级路径

- D-U-N-S 卡 3 周以上 → Apple 的 D-U-N-S 帮助页有 D&B "Call Me" 跟进入口
- 组织核实反复失败 → 可先用**个人账号**做 M0/M1 的真机调试与内测（功能等价），上架前再切组织账号；但 App Store 记录无法跨主体"改名"，只能 Transfer，越早定组织越好

## 参考

- [Apple: D-U-N-S Number 帮助](https://developer.apple.com/help/account/membership/D-U-N-S)
- [Apple: Program Enrollment 帮助](https://developer.apple.com/help/account/membership/program-enrollment)
- [Apple Developer Program](https://developer.apple.com/programs/)
