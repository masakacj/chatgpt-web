# ChatGPT Web iOS — v0.7.0 Native UX Parity 开发 / 测试 / 发布 / Handoff

> **状态：已批准规划，尚未开始本轮代码修改，未通过本轮验收，未发布 v0.7.0。**
> 日期：2026-10-11；仓库：masakacj/chatgpt-web；规划基线：main / v0.6.0 Build 221。
> **本文件是本轮 iOS 官方 App 式布局、全历史导航、新建聊天、单向按发送同步的权威 handoff。** 后续实施者必须先读仓库 AGENTS.md、本文件、IOS_MOBILE_SIDEBAR_051_HANDOFF.md、IOS_PC_COMPANION_050_HANDOFF.md，以及 mcpoffice PC_DEPLOYMENT.json / MOBILE_STRUCTURE_HANDOFF.md / MOBILE_CHANNEL_HANDOFF.md。

## 0. 已核对事实与尚未完成

- 2026-10-11 安装中心 GET /api/v1/apps/chatgpt-web/latest 已确认 **0.6.0 Build 221**，正式 GitHub release v0.6.0，安装中心：https://ipa.78175132.xyz/。原有网页模式保留。
- 仓库 main 的 SwiftUI 原生阅读界面为 App/NativeConversationScreen.swift；侧边项目/对话为 App/PCSidebarView.swift；PC 会话、草稿、发送、长轮询和协议为 App/PCCompanionView.swift；其余策略为 App/PCCompanionPolicy.swift。原生 UI 原有部分历史消息分页、工具交互确认、回执检查、离线快照。
- **已确认缺口**：App/PCSidebarView 只过滤已有 library.chats，并非全历史搜索；PC 侧库当前只来自已打开标签及已加载的官方侧边栏，不保证任意历史聊天可见；模型 apply(snapshot) 调用 draft.receive(PC draft)，另有「同步草稿」「采用 PC 草稿」；send() 先执行 sync() 再发 send 命令；未提供统一「新建聊天 / 项目内新建」闭环。
- 2026-10-11 最新名为「Mobile Controls 061」的 Actions 运行有失败/取消，不能视为已发布版本或验收。不要从该失败试验分支直接发布，也不要将本计划视为已编译完成。
- 当前专用 API origin **https://chatgpt-pc.781751.xyz:58443**；NPM 在 192.168.233.127；实际 PC Orchestrator 在 mcpoffice 的 D:\workspace\py\chatgpt-orchestrator；PC 默认 Chrome 生产扩展 ID hkpkilpjbeneliaiafdbkaomedgkkcmi。旧独立 chrome-extension-bridge、Tampermonkey 不是生产链路。部署前必须重新检查 PC live version/health，不以旧 handoff 代替实时状态。
- **本次只写计划/记录；未修改 iOS/PC 运行代码、未重载 Chrome/扩展、未发送真实消息、未构建/签署/上传 IPA。**

## 并行项目：PC Chrome Bridge 从 Orchestrator 独立迁出（2026-10-11 新增）

**权威独立迁移计划**：[`PC_CHROME_BRIDGE_DECOUPLING_HANDOFF.md`](./PC_CHROME_BRIDGE_DECOUPLING_HANDOFF.md)。此为 v0.7.0 的新增基础设施工作流；目前**仅完成规划，不代表独立插件已部署**。

- 将现有 Chrome MV3 扩展（官方页面状态、历史/项目交互、移动端受限写命令）从 Orchestrator 内嵌的 `extension/` 提取为独立开发/维护/版本发布的 **ChatGPT PC Bridge** 项目；将同进程 `src/mobile-bridge.js` / 3211 也拆成独立 Windows Bridge Service。Orchestrator 只保留可选 adapter 调用桥接能力，不能再是 iOS 同步链路的强依赖。
- **最终必须满足**：mcpoffice 的 Orchestrator 3210 未运行时，独立 Bridge 3211 + 唯一 Chrome 扩展仍能维持 iOS 配对、聊天读取、历史/项目能力（在官方网页支持的范围内）、手机显式一次 Send/回执；反过来 Orchestrator 正在工作时必须通过互斥租约避免冲突，不损坏现有编排功能。
- 统一分阶段 **M0 依赖审计 → M1 独立源码仓库 → M2 服务进程拆分 → M3 可选编排 adapter/互斥 → M4 迁移/同扩展上线 → M5 iOS 真机联调 → M6 清理旧所有权**。P0/P1/P4 的 iOS 原生布局、本地草稿和 fixture 测试可与 M0-M3 并行；新协议的真实发送、新建、项目内新建和正式发布须以 M4/M5 的独立服务实证为准。
- **原路径和稳定性**：生产扩展 ID `hkpkilpjbeneliaiafdbkaomedgkkcmi`、PC Default Profile、配对 Key、旧手机兼容协议、持久命令 journal、原生状态存储必须无损保留。安装目录迁移可能改变 unpacked ID，应先独立源码/稳定发布路径，再在实证可保留身份后迁移安装目录，绝不新旧双扩展并行对同一页面操作。
- 保持 `https://chatgpt-pc.781751.xyz:58443/v1/*`、127.0.0.1:3211、NPM/WireGuard/AliDNS 不变。**此轮不得提前停止 Orchestrator、重新部署基础设施或将新项目计划误写为已发布**。

## 1. 产品目标与用户不可妥协的行为

1. **官方 App 类似的原生布局和操作逻辑**：原生 SwiftUI 顶部导航、左侧项目/历史侧边栏、聊天正文、底部输入框、新建按钮与键盘/返回/焦点行为。以主流官方 App 体验为交互参考，不要求复制品牌资产或内部代码；暗/亮色及安全区域、VoiceOver、动态字体按 iOS 规范实现。
2. **可进入任一账号中官方网页能够定位的聊天**，包含非当前 Chrome 标签、非当前已加载侧边栏、项目内旧聊天；支持按需全历史搜索、分页/加载更多及官方 UI 提供的历史入口。**绝不将「当前已加载的几十条」冒充全历史**。归档/特殊历史若官网 UI 不可检索，需明确状态及限制并专项验证，不能编造来源。
3. **新建普通聊天、在指定项目中新建聊天**。手机点击新建应立即出现空白本地会话/独立输入框；建议首条消息点击发送时才使 PC 官方网页创建真实会话，避免空对话污染历史。项目归属必须通过 PC 官方页面确认，失败不得静默退化成普通聊天。
4. **严格单向输入规则**：手机独立本地草稿，打字、失焦、切对话、切后台、断网及恢复，都不将草稿写入 PC。**只在用户明确点击手机发送后，才在 PC 原编辑器填入该条文本并点击官方发送**。PC 输入框内容不自动复制/回填到手机，也不覆盖已有手机草稿；移除「同步草稿」「采用 PC 草稿」入口。PC 草稿可以只传 hash/占用标志用于防冲突，不传文本到手机编辑器。
5. 消息与状态依然从已配对 PC 官方页面读取；隐藏普通思考和工具过程，只保留精简「思考中 / 生成中 / 需交互 / 已完成 / 错误」反馈及可安全操作的明确确认卡片。原网页模式作为保底。
6. **防重复发送和防跨会话误发高于 UI 模仿**：未知回执不得自动重放、旧文案不得写入新会话、PC 未发送草稿不得被覆盖、PC 当前用户操作和 MCP 授权不得被抢占。

## 2. 交互结构（原生，不嵌入隐藏网页）

**主聊天页**：
- 顶栏：左侧「☰」打开原生侧边栏；中部当前聊天/项目名（必要时可点击查看归属）；右侧「新建聊天」和简洁更多菜单。连接设置收进更多菜单，不占主要一级操作。
- 正文：用户消息靠右气泡，助手正文靠左、支持 Markdown/代码/复制/链接；历史向上分页；生成态可见；必要的工具交互需二次确认；长消息保持懒加载，切换聊天时绝不短暂显示上一会话正文。
- 底栏：自适应多行编辑器、可用的附件占位/能力入口（不可用功能明确引导原网页或 PC）、右下角发送；点击正文空白关闭键盘，键盘出现时不盖住按钮；切对话保存每个对话独立草稿。没有「同步」按钮或 PC 草稿导入。
- 新建普通聊天：立即渲染空白本地会话，可返回/切走并恢复草稿；只有点击发送才在 PC 执行「创建 + 发送」一次。
- 新建项目聊天：用户先选择项目，进入项目名明确可见的空白会话；第一次发送才按官方项目入口创建并发送，结果需验证项目归属。

**侧边栏**：
- 固定最上方：新建聊天、搜索全部历史（不是当前列表字符串过滤）。
- 「项目」按官方可见分组逐项加载，项目行提供展开、在此项目新建聊天；展示项目名/所含对话、列表末尾加载更多。
- 「最近对话」和搜索结果展示对话名、项目归属、PC 确认过的进行中/完成/错误/已读状态；切换后当前选择高亮。
- 搜索结果分页并允许打开任意已核实结果，不强制该聊天已在 Chrome 标签打开；若服务器无法确定是否完整，显示「加载更多 / 官方未提供全部记录」，不能显示「无结果」误导。
- 交互：侧栏打开与关闭、点击空白、导航返回、新建按钮、输入获取焦点/键盘隐藏均复刻 iOS 常见行为。不要重新加入已明确取消的全局自定义触摸手势。

## 3. PC 历史检索与导航的可行性门槛

**关键风险**：现有 /v1/library 仅镜像 PC 官方侧栏已渲染的有限条目；单靠扩大前端数组/循环扫描 DOM 无法得到全历史。

实施路径：
1. 先在 **现有用户已登录的 PC Chrome 默认 Profile** 进行只读 UI 能力审计（不得读 Cookie、抓私有 ChatGPT 历史 API、截获请求或将登录交给其他 Profile），确认官方网页的历史搜索、项目展开/滚动、归档入口可按需驱动，结果 ID/标题/项目关系/打开后的路由是否可证实。
2. 在现有 mcpoffice Orchestrator 扩展上新增 **用户触发** 的受限搜索能力：搜索文本由手机提交，PC 在官方 UI 中检索，返回有限且去重的结果/来源/nextCursor/partial，不做后台全量扫描、不在服务端永久留正文/检索词。推荐沿现有 /v1/library 受限服务扩展独立搜索动作，正式路径/字段以契约测试冻结为准。
3. 结果只能按 **扩展实际从官方 UI 观察并核实的 conversationId 与 route** 导航。禁止任意用户传入 URL、无校验的 conversationId 拼接、猜测项目归属。当前 PC 窗口繁忙、IME 编辑、未发送 PC 草稿、等待 MCP 交互时不抢占现有用户；优先评估独立、受控、复用既有登录态的 companion Chrome 标签以避免修改 PC 正在使用的原标签，但不自动创建新的登录/profile。
4. 任何访问失败必须区分：未查到、尚未加载、PC 页面错误、登录失效、数据不完整。若官方 UI 无法索引全部历史，要在技术门槛阶段给出证据和受限回退；**不许宣称「任意对话已支持」**，也不可以为赶发布偷偷引入未审查的 ChatGPT 内部 API。
5. 侧栏模型与会话路由使用同一套 server-proven identifiers；项目范围查询和打开后的归属再验证一致。

## 4. 单向手机草稿与「点击才发送」协议

**iOS 本地**
- 按「PC 连接身份 + 会话 ID / 临时新建 ID」隔离草稿及光标，持久化到受保护 Application Support（原有排除备份/Keychain 配对策略不变）；不被 snapshot.draft 更改。切任意会话可保留各自草稿，不能因切换阻塞列表导航。
- 任何 UI 输入（包括输入法正在组字、后台恢复）只更新手机本地状态；手机没有 PC 草稿覆盖/合并按钮。snapshot 仅消费 **PC canSend / busy / hash / confirmed status** 用来防发送冲突。
- 手机发送一按：立即反馈按下态并冻结**这一条**文本/版本/目标，先持久化不可重复提交的 commandId + 草稿版本；本地存储失败不能发出 POST。随后仅发一次有明确目标的写请求，双击只读取同一回执。用户继续输入的新草稿版本不被晚到回执清空。
- 新建会话使用临时 ID，只有首次发送 PC 真实创建/确认后绑定返回的真实 conversationId。项目新建要求 server 返回并验证 projectId；无法确认时保留本地草稿并报告待核对。
- PC 已有未发送草稿时，优先在独立执行标签隔离；否则拒绝覆盖/发送并告知用户去 PC 处理，不导入 PC 草稿文字。

**PC 一次性执行命令**（协议提案，尚未实现）：
- 基于现有 authenticated /v1/ 及持久 command journal，定义一次性的 compose-and-send 命令（最终 route 在实现前定稿），目标区分 existing / new / new-in-project；字段包括 commandId、text、localRevision、target / verifiedProjectId、expectedDocument 或 route token、预期 PC draftHash/idle 状态和有效期。
- PC 在一个防重事务内完成：校验身份/占用/route、必要时从已验证官方 UI 导航/创建聊天、确保 editor 未被用户占用、**仅在收到发送命令后**填入 PC 编辑器并点击官方发送一次、观察网页中新用户消息与实际 conversationId/项目 ID、写 durable receipt。
- 不能以「文本已写进 PC 输入框」当作发送成功；**只有确认网页出现对应新用户消息/会话后才返回 sent_confirmed**。操作在点击前失败返回明确 not_sent；点击后结果不明为 unknown，只能 GET receipt/人工核对，绝不自动补发 POST。
- 不在普通浏览会话、搜索、获取快照、手机输入时调用旧 syncDraft()；移除「手动同步/PC 草稿接收」的用户功能。旧客户端与服务协议至少一个过渡版本兼容，能力协商 fail-closed（服务器缺新能力则显示不可用，不能退回会自动回填的旧路径）。
- PC 原始浏览器 tab / MCP 授权 / 草稿 / 重放防重 journal 必须保留，不得在构建/回退时清空。长轮询只读维持当前分离设计，写操作不排队自动重试。

**可追踪状态机**：local_draft → queued_locally → accepted_once → navigating_or_creating → clicked_once → sent_confirmed / definitely_not_sent / unknown_check_receipt。新建与项目新建在 sent_confirmed 前仍可显示临时会话，并可用同一 commandId 恢复查询。

## 5. 分阶段开发与交付顺序（不同时修改所有层）

**P0 — 基线与官网操作能力验证（放行门槛）**
- 固定 main v0.6.0 Build221、PC live audit、现有回执/Keychain/协议与最新 0.6.1 失败试验差异；创建独立 feature 分支，例如 feature/ios-native-ux-070-20261011，不覆盖未验收的试验分支。
- 用现有默认 Chrome（官方登录 Profile）核验历史搜索/项目创建/切换 UI；记录可复现的页面结构、空结果/加载、分页边界、点击新建、项目归属验证；不触碰实际聊天的编辑与发送。
- 输出冻结的「历史检索 + 一次发送 + 新建/项目新建」协议草案、兼容/幂等状态机。若任一历史不能检索，先给出范围风险/回退，不得直接宣称完成需求。

**P1 — 安全数据层、手机本地草稿 + 单次发送**
- 修改 App/PCCompanionView.swift / PCCompanionPolicy.swift：按会话本地草稿、去掉 PC->手机草稿接收、删 syncDraft UI、原有回执防重复迁移到单次提交。
- 在 mcpoffice D:\workspace\py\chatgpt-orchestrator 现有 Orchestrator / Chrome 扩展加入一次性 compose/send；继续保留官方 UI 发送与只读快照。先跑 Node/扩展和 Swift 纯策略测试，再接真实服务。
- 门槛：手机连续输入/退后台/切 3 个聊天后 PC 输入框完全不变；一次手机 Send 导致最多一次 PC 原生点击；失败保留草稿且可查询回执；PC 草稿绝不覆写手机输入框。

**P2 — 全历史/项目浏览和可靠切换**
- 扩展按需官方 UI 检索、带来源的有限分页/项目展开、已验证路由选择；SwiftUI 侧栏展示搜索、项目、最近、加载更多。现有 PC/手机草稿及命令都要按 owner/route 限制。
- 门槛：可打开 **不在 PC 当前已打开标签与首屏侧栏里的旧聊天**；在项目范围/全局搜索得到的同一会话 ID 一致；切换不会显示旧对话正文/错绑新草稿。官网无法检索的归档等要可见受限状态。

**P3 — 普通新建 + 项目内新建**
- 先实现手机本地空白会话/草稿；首次发送才按官方 UI 在 PC 新建并执行一次发送；项目归属核对不允许无声降级。
- 门槛：普通聊天真正进入账号最近记录；项目内聊天进入正确项目；取消新建或只输入未发送不产生 PC 新对话；重启 iOS 后仍能恢复临时草稿/未决命令。

**P4 — 官方风格 UI 与流畅度**
- 重整 App/NativeConversationScreen.swift、App/PCSidebarView.swift：官方近似信息层级、标题/菜单/侧栏、简洁状态、文本与代码布局、键盘/安全区域、暗/亮色、原生惯性滚动、VoiceOver；不实现全局自定义手势。
- 保留已实现历史正文分页、工具明确交互确认、完整回答、原网页 fallback。最大化复用当前 SwiftUI LazyVStack / 增量快照；避免大列表/长消息主线程全量重排。
- 指标分清本地响应和 PC 网页获取时间：点击/输入有即时可见反馈；本地有缓存时先显示缓存；采样冷启动、打开列表、切旧会话、长聊天滚动的 p50/p95、峰值内存、掉帧、取消旧请求有效性。

**P5 — 全链路验收、beta、正式发布**
- 通过所有 CI、真实 PC 默认 Profile 安全审计、签名内部 beta 真机认证链路、覆盖安装和回退演练后，才将计划版本 v0.7.0 作为正式最新版本发布。阶段不允许自动越过下述门槛。

## 6. 必须执行的测试矩阵 / 量化证据

**基础自动化**：
- Swift 单元/纯策略：独立 per-conversation drafts、不同 PC 身份隔离、晚到 snapshot 不改草稿、IME/空白/双击、防重 journal 持久化、跨目标切换、命令版本/route 冲突、新建临时 ID -> 官方 ID、项目 ID 核对、unknown 与回执恢复、iOS 进程强杀恢复。
- Node / Chrome MV3：真实 Chrome 受控测试页（fixture）模拟官方 DOM 搜索分页、项目树、创建/发送、按钮位置/本地化变化、disabled/Stop 误识别、点击前失败、点击后回执丢失、MCP approval/PC 未发送草稿占用。**每条发送只一次 click**，不能重放。
- iPhone Simulator UI：新建/项目内新建/列表检索/搜索结果切换、键盘弹起和点击空白收起、编辑器多行、返回/侧栏关闭、深/浅色、小屏、竖屏及 Dynamic Type；P1-P4 原生模式保证 app.webViews.count == 0；保留原 WKWebView fallback 回归。
- 协议端到端仿真：POST 写请求次数、异步回执、断网/503/410/401/403/429/路由改变、旧返回晚到、PC 重启、手机杀进程、切项目、旧命令 pending、新文本编辑仍保留；所有失败不得产生重复官方发送。

**真实环境验收（明确指定独立测试对话，不向真实业务聊天写入测试消息）**：
1. 登录配对 iPhone 后，在手机选择一个 PC 不在首屏/未打开的历史对话并加载正文；记录会话 ID 一致、未加载/加载失败提示。
2. 手机上的 2 个旧聊天和一个本地新聊天分别输入草稿，反复切换、断网、恢复；PC 原编辑器没有因手机打字被写入，手机草稿互不覆盖。
3. 在 PC 原编辑器手动输入不发送，确认手机原输入框文本完全不变；按发送时对 PC 占用安全失败而非覆盖。
4. 手机首次发送新普通聊天，观察唯一一次官方发送，新会话 ID、标题/最近记录、回复正确；确认手机只清理已发送的那条草稿。
5. 手机在指定项目下新建并首发，PC 官网实际项目归属一致；项目错误必须中止且保留待发送草稿。
6. 手机旧聊天明确点一次发送，网页仅有一条新用户消息；模拟掉线/回执丢失后仅查询 receipt，不重复 POST；继续输入第二条文本时不被第一条回执抹掉。
7. 官网长对话/几百条历史与多个项目，向上历史分页、快速切换、收键盘、返回原网页、不出现白屏或误绑正文；性能 p50/p95/内存对照 v0.6.0。
8. iOS App 后台/恢复、杀进程重启、PC Chrome tab 更换/扩展热重载、PC 断网及重新上线、NPM 通道暂断、手机 Wi-Fi/蜂窝切换都不丢已保存草稿或重发旧命令。

**零容忍阻断**：任何自动重复发消息、错误会话/错误项目发消息、未经手机 Send 修改 PC 草稿、PC 草稿反向覆盖手机输入、未确认却显示发送成功、私钥/Token/正文/搜索词进入公共日志、权限/证书验证绕过、覆盖更新清空原用户会话/未决命令。

## 7. 发布计划、验收门槛与回滚

1. **开发分支**：从稳定 main 分离，实现时小步提交 PC 服务、原生模型、视图、自动化测试；不能直接采用失败的 0.6.1 Actions 结果，也不能仅凭 GitHub commit 宣称 PC Chrome 已实际启用扩展。
2. **隔离 CI**：GitHub Actions 使用已有 macOS/iPhone device compile、Swift strategy tests、真实 Simulator UI 及 full native regression；PC 先执行 D:\workspace\py\chatgpt-orchestrator 的 npm test、MV3 fixture 和原有 resilience tests，再按现有空闲安全协议热更新**同一个扩展**（不重启 Chrome/用户标签、不删 journal）。发布前至少一次真机真实 paired read/send/new/project-new 闭环。
3. **受控 beta**：签名预发布构建供真实 iPhone 验收，若安装中心支持独立测试通道，应使用它而不是过早覆盖公开 latest；否则必须先保障回退、明确区分 beta 和正式渠道，并征得正式发布批准。通过同 Bundle ID 覆盖安装，不删除 App、不清 Keychain、Cookie、草稿、历史缓存或 PC receipt journal。
4. **正式 v0.7.0**：仅在完整测试矩阵绿色且真实 iPhone 验收通过后 merge **经过测试的精确 commit SHA**，再用既有 GitHub Actions 签名/安装中心流水线。核对 Actions 完整 build/sign/upload/UI job、安装中心 GET latest 返回准确版本/Build/Bundle ID、实际 GET manifest 和签名 IPA 字节流/hash；不能用 unsigned GitHub IPA、HEAD404 或「release 存在」替代已签名安装证明。
5. **发布后**：比对 iOS 首次打开、侧栏、搜索、普通/项目新建和发送；记录 crash/blank screen/长对话性能；仅上报去标识的有限诊断事件，不记录内容、配对密钥和浏览历史。
6. **回滚**：以已签名可安装的 v0.6.0 Build221 为参考（首先核验证书和下载有效），只回滚新原生 UX 和本次扩展/命令协议改动；保留兼容读取和历史 commandId，避免重复消息；不重建 NPM/AliDNS/WG，不恢复废弃用户脚本，不清理原 ChatGPT Cookie 或 PC journal。若 PC 不可用，显示本地只读缓存 + 本地草稿而非隐式切回会误发的旧协议。

## 8. Handoff：接手顺序与更新规程

**代码权威位置**
- iOS GitHub：masakacj/chatgpt-web；源文件 App/NativeConversationScreen.swift、App/PCSidebarView.swift、App/PCCompanionView.swift、App/PCCompanionPolicy.swift；测试 UITests/NativeChatReaderUITests.swift、UITests/PCSidebarUITests.swift、UITests/PCCompanionUITests.swift；相关 CI .github/workflows/native-chat-ui-check.yml、mobile-sidebar-check.yml、ios.yml。
- PC 唯一生产源：mcpoffice D:\workspace\py\chatgpt-orchestrator（现有 extension、Orchestrator、部署 JSON 和 MOBILE_* handoff）。Chrome 只用默认 Profile 的已安装扩展；登录 Broker/会话沿既有路径。
- 网络：iOS → https://chatgpt-pc.781751.xyz:58443 → NPM 192.168.233.127 → 已有 WireGuard relay → PC 受限 3211。mcpdebian 是部署管理通道，不是日常消息中转；**本计划不要求改动网络拓扑**。
- iOS 源码与 IPA 不落到 MCP 服务器；通过 GitHub branch/PR/Actions/安装中心走完整构建。即便只做验收也不打断用户的正常 Chrome workflow。

**本轮已完成**
- [x] 审阅 v0.6.0 主分支原生主界面、侧栏、草稿接收/发送逻辑与既有 handoff。
- [x] 核实安装中心为 0.6.0 Build221；确认后续 Mobile Controls 061 测试存在失败，不算发布。
- [x] 冻结用户明确的交互目标、PC 单向提交、全历史检索可行性前置门槛及 0.7.0 阶段计划。
- [x] 记录本轮开发/测试/发布/回退计划；**只更新文档**。

**下一轮执行清单（全部待完成）**
- [ ] P0 通过官方网页真实 UI 核实历史搜索与项目新建可行性，保留只读证据；当前无法保证「任意历史」全覆盖。
- [ ] 定稿经过审查的后端 action/schema/错误码及版本协商，加入端到端 fixture。
- [ ] P1 本地 per-chat draft、发送前不写 PC、一次性 send + durable receipt；PC->手机草稿接收完全取消。
- [ ] P2 项目/最近/全历史搜索分页、任何可验证结果打开，不再只靠当前侧栏 DOM。
- [ ] P3 新建、项目新建，首次发送绑定真实会话，确保项目归属。
- [ ] P4 官方 App 风格界面/键盘/焦点/性能/可访问性。
- [ ] P5 CI、PC 真环境安全验证、iOS 真机 E2E、受控 beta、正式发布/回滚。
- [ ] 每次里程碑完成后，在本文追加：GitHub 分支/commit、PC extension + server live版本、测试和 Actions run ID、真机结果、缺陷/未满足验收、实际签名 IPA build/manifest/latest，**不可把测试计划当成测试通过**。

**停止条件**：未确认官网全历史查询可行性不得承诺全部历史支持；没有实际真机一次发送/项目正确归属验收不得正式发布；任何发送幂等/草稿隔离失败先停发布，保留上一稳定签名版。
