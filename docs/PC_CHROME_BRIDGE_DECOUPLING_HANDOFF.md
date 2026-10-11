# PC ChatGPT Bridge 独立化 — 开发 / 测试 / 发布 / 迁移 Handoff

> **新增计划（2026-10-11），尚未实施。** 本文为独立 Chrome Bridge 插件和本地服务迁移的权威规划记录，不代表源码已迁移、扩展已重装或新版本已发布。关联 iOS 规划：[`IOS_070_NATIVE_UX_PARITY_HANDOFF.md`](./IOS_070_NATIVE_UX_PARITY_HANDOFF.md)。
>
> **产品方向**：PC 端 ChatGPT Chrome 桥接扩展从 `chatgpt-orchestrator` 中迁出，成为可独立开发、测试、发布、升级和运行的项目。Orchestrator 以后只是其可选调用者，不能再控制该插件核心代码或成为 iOS 同步服务的强依赖。

## 1. 当前事实（2026-10-11 只读代码审计）

- PC 生产位置：mcpoffice Windows，`D:\workspace\py\chatgpt-orchestrator\extension`；Default Chrome 用户 Profile 中唯一扩展 ID `hkpkilpjbeneliaiafdbkaomedgkkcmi`。**禁止新装第二份生产扩展与原扩展抢占同一网页**。独立旧 Profile `D:\workspace\chrome-extension-bridge` 已退役，不是目标位置。
- 本轮读取的 `PC_DEPLOYMENT.json` **声明** manifest `0.5.4`、executor `pc-extension-v43-mobile-controls`、resilience `1.1.2`、mobileCompanion `0.3.2`，其最新 iOS 发布登记 `0.6.0 Build221`。**此处是部署登记，不代替后续执行前对 /api/health 和实际 Chrome sentinel 的 live audit**。
- `extension/background.js` 既是 Orchestrator executor（工作流任务、归档、删除、冷却时间、`ws://127.0.0.1:3210/executor`），也直接初始化 `startPcResilience` 和 `startMobileStructure`。
- `extension/content.js` 是旧编排任务执行入口；`pc-resilience-{background,content,core}.js` 负责官方原生状态/安全读取恢复；`mobile-structure-{background,content}.js` + `mobile-sidebar.js` + `mobile-presentation.js` 提供移动端已配对会话、侧边栏/有限历史、原编辑器操作。
- `src/server.js` 在 Orchestrator Node 进程内 `createMobileBridge()` 并绑定 `127.0.0.1:3211`；`src/mobile-bridge.js` 的消息通过 Orchestrator 自身 `sendToOneExecutor` / `/executor` WebSocket 向扩展转发。Orchestrator 原有管理端 `127.0.0.1:3210` **不能公网暴露**。
- 3211 现有受保护链路：iOS → `https://chatgpt-pc.781751.xyz:58443` → NPM `192.168.233.127` → WireGuard/relay → PC `10.77.0.4:3211` → 127.0.0.1:3211。NPM 不在 mcpdebian 上，后者仅用于基础设施管理。
- 当前鉴权 Keychain/Bearer + PC 私有 `data/mobile-companion/pairing.json`；服务端 durable `commands.json` + 扩展 `chrome.storage.local` 的 `mobile-send-v1:<commandId>` / `mobile-interact-v1:<commandId>` 双层防重。PC 状态与读取预算键 `pc-state-v1:`、`pc-recovery-v1:`。
- 以上表明：**仅将 extension 文件夹复制到新目录不算解耦**；必须解除 Orchestrator 进程对 3211 服务的拥有权，重建扩展与服务独立通道，且不损坏编排器任务执行。
- 未做：新独立仓库创建、新本地常驻服务部署、Chrome 重装/热重载、端口更换、配对密钥迁移、生产测试消息/工具点击。

## 2. 目标边界与源码所有权

**规划名称**：`ChatGPT PC Bridge`（Chrome MV3 插件 + Windows 本地 Bridge Service）。规划 GitHub 仓库名可用 `masakacj/chatgpt-pc-bridge`、mcpoffice 本地源码目录可用 `D:\workspace\py\chatgpt-pc-bridge`；**目前仅为候选命名，不能声称仓库/目录已经建立**。工作进程、自动更新与服务注册在 M1/M2 阶段决定。

| 归属 | 迁移后负责 | 不再负责 |
|---|---|---|
| 独立 Chrome Bridge 扩展 | ChatGPT 官方页面 DOM 适配、原生状态/未读与安全读取恢复、可验证历史/项目 UI 读取、手机命令单次执行、扩展状态和权限、审计 sentinel | Orchestrator 的任务调度/工作流规划或 iOS UI |
| 独立 Bridge Service（PC） | 本机 3211 的 /v1/ 受限鉴权 API、配对管理、会话订阅/长轮询、回执与 commandId journal、扩展专用 IPC 和健康检查 | Orchestrator 的 3210 管理面 /executor、业务节点队列 |
| Orchestrator（既有） | 工作流调度、跨对话任务、并发与限流策略、结果聚合、必要时通过**可选适配器**请求浏览器执行 | 持有桥接源码、启动/重启 Bridge 3211、维护 iOS 配对 Key 或手机 Send 回执 |
| ChatGPT Web iOS（既有 GitHub） | 原生 App、侧边栏/消息/独立手机草稿、Bridge API 客户端、iOS 测试与签名发布 | 在手机直接调用 ChatGPT 隐藏 API、管理 PC 扩展或持有 PC 网站 Cookie |

**一份生产扩展原则**：保留同一个已安装 ID、Default Profile、现有储存键、浏览器登录与所有标签。Orchestrator 若仍需 executor，独立扩展可以加载 **可选 `orchestrator-adapter`**，保持既有工作流调用语义；**不能靠同时安装老 executor 和新 bridge 两个扩展分别修改同一个 ChatGPT 页面**。

独立 Bridge 启动条件：在 `3210` 关闭且没有 Orchestrator Node 进程时，扩展仍能被动管理状态、接受已配对 iPhone 的只读和授权操作（需要 Chrome + Bridge Service + 既有网络通道在线）；Orchestrator 连接失败只影响编排工作流，不影响独立 Bridge 的核心能力。

## 3. 建议的工程目录与稳定接口

建议新的独立项目目录（规划，非实际文件）：

```text
chatgpt-pc-bridge/
  extension/                # 唯一 MV3 扩展；page adapter、状态、可选 orchestrator adapter
  service/                  # 独立本地 Bridge Service，拥有配对/会话/回执
  protocol/                 # /v1 wire schema、错误码、能力协商、兼容契约
  tests/                    # Node、Chrome MV3、端到端 fixture、升级回退用例
  scripts/                  # 只读 audit、校验/备份、原地热更新/恢复、发布
  docs/                     # ARCHITECTURE、DEPLOYMENT、RELEASE、MIGRATION、HANDOFF
  .github/workflows/        # 独立 CI、打包与版本发行
```

**通信**：
1. iOS → 原封不动的 `https://chatgpt-pc.781751.xyz:58443/v1/*`（无需重新申请域名、DNS、证书、修改 WireGuard 或 NPM host；依旧只有 /v1/ 对公网可见）。
2. Bridge Service 仅监听 PC `127.0.0.1:3211`，由**独立 Windows 服务/受控进程**运行；与 Orchestrator 3210 不共进程。新 service 独立持久化 pairing、commandId、sessions/leases、健康状态，启动失败必须拒绝写入而非回退到不安全接口。
3. 扩展 ↔ Bridge Service 走仅 localhost 的专用受限 IPC（MV3 service worker、独立连接、来源/扩展身份校验、握手令牌与最小权限）；不通过 Orchestrator 的 WebSocket 代转发。**协议不得把管理权限、Cookie、CDP debugger 或任意站点 URL 暴露给 iOS**。
4. Orchestrator ↔ 可选 adapter：最小化的**单向授权任务请求与回执**，只在工作流启用/连接时激活，保持已有 `/executor` 兼容或以版本化接口替换。必须验证原始执行/归档/删除任务与移动端互斥，不允许两条连接分别执行同一个命令。
5. **仲裁**：扩展为每个 PC tab 的唯一实际执行者，写操作持有有期限的 tab/会话租约；Orchestrator 正执行、PC 正编辑/IME、官方在生成/等待审批、手机 pending/unknown 时手机发送 fail-closed；不得让桥接服务误判 Orchestrator 离线代表「空闲」。跨进程 busy 信号过期/丢失视为「未知、不可写」，只读仍可按安全规则继续。
6. **旧版兼容**：v0.6.0/Build221 手机继续使用现有 /v1/ schema1/已有配对秘钥和命令回执；新的「手机仅点击发送后提交」行为通过新的 `capabilities`/协议版本/端点显式协商实现，不能向旧客户端返回具有不同语义的成功信息。项目内新建/全历史搜索 API 在验证官方 UI 后才确定，不得编造内部 ChatGPT API。

**服务设计细节需实证定稿**：将现有服务 `src/mobile-bridge.js` 的代码/测试归属转至独立项目；在测试环境先替代 `sendToOneExecutor` 路由，而非以字符串重命名让它仍依赖 3210；把旧 `background.js` 的执行器职责提成 adapter、Bridge 连接逻辑提成模块；内容脚本保留官方 DOM 不破坏。禁止随意合并/移除安全守卫、状态恢复预算或命令写前持久化。

## 4. Chrome 扩展 ID、源目录、状态迁移的硬约束

**直接换扩展安装路径可能改变 unpacked Chrome 扩展 ID**，从而造成 `chrome.storage.local` 历史状态与已验证扩展 ID 不可访问。严格两步：
- **源码先独立、部署路径暂时保留**：第一阶段新独立仓库是唯一源码来源，现有 `D:\workspace\py\chatgpt-orchestrator\extension` 仅保留为一个可校验的**旧安装落地点/回退映像**，停止在那里继续独立开发。热重载仍按既有安全方式，不重启 Chrome。此阶段源码已经独立，安装路径尚未迁离。
- **独立安装目录后迁**：通过官方 Chrome 支持的方法实测固定扩展身份/ID 能否在不清除数据情况下切换到 `D:\workspace\py\chatgpt-pc-bridge\extension`；**不能假设移动目录自动保留 ID**。如无法做到，在保持老已安装扩展期间禁止强制迁移；需额外设计受控单次身份/存储迁移及用户确认（不得复制网站 Cookie、OAuth 密码），验证所有待发回执/状态/配对关系后才下线旧 ID。禁止同时启用双扩展。未经成功迁移，旧目录部署兼容层需保留。
- 服务私有文件从 `D:\workspace\py\chatgpt-orchestrator\data\mobile-companion` 迁出须 **ACL 限制 + 离线校验 + 原子切换 + 备份校验**。传输时不可在 stdout、GitHub、CI artifacts、遥测或 handoff 暴露 pairing key / 正文 / command journal。保留原 commandId 的永久或足够长期防重墓碑；不能因新服务首次启动重新生成 key、清空 pending 或漏掉 `unknown`。
- **只有一个 3211 的权威监听者与写入者**：迁移使用临时仅本地测试端口先验证，新旧服务不能同时对同一个 pairing/journal 接单；切换窗口在 pending=0、Orchestrator 工作流空闲且无用户授权/PC 草稿冲突后进行写入封锁、持久化快照、停旧监听、切换独立服务、验证外部 401/403/200 与回执，再撤销封锁。任何异常恢复旧服务且保留旧/新所有 ID 预留记录；不自动补发。
- 移动端断线、丢失状态可重新订阅只读；**绝不重新执行已点击、点击结果未知、已确认的 Send/工具动作**。后续浏览器恢复、原生错误状态/未读蓝点等旧策略行为必须一致。

## 5. 迁移开发阶段（M0–M6）和与 iOS v0.7.0 的依赖

| 阶段 | 交付 | 验收 |
|---|---|---|
| **M0 依赖审计/冻结** | 记录当前文件清单、`3210/executor` 消息与 `3211/v1` 契约、权限/扩展 ID、已验证版本和实际后台任务 | 能画出模块调用图与持久化清单；新旧源 SHA 与 live runtime 区分 |
| **M1 新项目结构** | 新独立 GitHub 仓库/本地工作区、可复现 MV3 build/打包、独立测试与 release 版本号；原代码镜像但只读生产 | 新工程在未启动 Orchestrator 的隔离 Chromium 里可以加载；未碰生产 |
| **M2 Bridge Service 抽离** | `mobile-bridge`、pairing、journal、`3211` 独立进程，独立健康/配置/Windows 启动与恢复 | 停 Orchestrator 的测试副本，独立服务仍能与测试扩展完成 read/Send/receipt；原 /v1 安全用例一致 |
| **M3 Orchestrator adapter/仲裁** | 扩展后台拆分 Bridge 主逻辑和可选原 executor 协议适配器；隔离独立 Bridge / Orchestrator 任务占用 | Orchestrator 暂停不影响 Bridge；Orchestrator 正忙不得插入手机写；原工作流不退化，不出现双消费 |
| **M4 原地发布与迁移** | 已签名/已校验 release 包、同扩展安全替换方案、服务切换/回滚脚本、私有数据一致性核对 | 只有 1 个生产扩展、1 个 3211 主监听，原 ID/草稿/状态/journal/配对保留；外网通道不变 |
| **M5 iOS v0.7 联调** | 独立服务支持新手机版本能力协商、全历史官方 UI 检索（若可验证）、单向仅发送提交、普通/项目新建；旧客户端兼容 | 真机接入独立服务，新旧 iOS Send 单击防重，项目归属正确，Orchestrator 关闭仍可用 |
| **M6 清理遗留所有权** | Orchestrator 停止编译/打包扩展、去除 3211 server 持有权；配置其 optional adapter 并记录运行目标 | Orchestrator 不再含权威插件源/自动升级逻辑；文档与部署 JSON 指向新项目；无旧后台自动重启争用 |

**和原 iOS 计划的关系**：
- iOS 的 UI/layout 和本地草稿纯测试可以并行做，不必等 M4。
- iOS 的真实历史搜索、新建聊天、首次发送和真实网关联调 **依赖 M2/M3 确定的协议和事务边界**；两个项目用版本化契约/fixtures 协同。
- iOS 正式版不能声称「独立 Bridge 已上线」直到 M4/M5 实测；如迁移未过门槛，可继续保持稳定 iOS v0.6.0 与当前 PC 服务，不为赶进度绕过安全门槛。

## 6. 必须通过的测试

**代码/契约**：Node + MV3 Chrome 实例 + Swift iOS fixture；旧版协议回归、新版能力协商、服务重启/掉线、重复 commandId 与不同 body hash、401/403/429、Bearer/Origin/TLS、不允许任意 URL /private ChatGPT API/CDP 或 /api 管理端；浏览器扩展最小权限审计（去掉不再必要的权限要在功能证明之后）。

**用户数据和状态**：同一 ID 的 `chrome.storage.local` 状态历史/未读/失败预算和 `mobile-send-v1` 保留；pairing Key 保持；临时会话、草稿和命令 journal 可恢复；未知命令不自动重发；正式版本变更不能清 ChatGPT Cookies、IndexedDB、历史 DOM 或 MCP 授权上下文。

**真实 Chrome**：默认 Profile 上实测同一扩展 ID、唯一 service worker、唯一通信连接、无旧重复注入、原生错误识别、MCP/附件完整；原有 Orchestrator 新开/归档/删除任务与 companion 读/写互斥；Chrome 完全关闭/重开与扩展热更新后恢复状态。任何可能发送的真实功能使用明确选定的独立测试聊天，真实生产业务聊天只读诊断。

**断 Orchestrator 的关键门槛**：在不破坏当前生产工作流的**隔离测试环境**关闭 Orchestrator 3210，Bridge 3211、浏览器状态/手机读取/显式一次 Send/回执仍工作。完成后才在安全维护窗口验证生产的 Orchestrator 进程独立停止不会拖垮 Bridge；禁止为了验收直接停正在运行的 Orchestrator。

**网络兼容**：公网入口不变；只允许 /v1/、无密钥 401、非法 Origin 403、内部管理 /executor/CDP 404/隔离；20s 长轮询不被中继提前断开；证书验证不降级。异常断线显示离线快照/本地草稿，绝不盲目自动 Send。

**可量化结果记录**：发布包 hash、GitHub commit/tag、CI run、Node/MV3/iOS case passed count、部署前后目录/扩展 ID/服务 PID/监听、原有 3210 workflow health、3211 private+public health、真机 read/send/receipt、故障转移和回滚证据。

**零容忍**：双扩展、双 3211 writer、ID 变化却无状态迁移、commandId 防重丢失、PC 端非用户同意的草稿覆盖/发送、Orchestrator 管理口曝光、密钥外泄、原有工作流被停止/损坏。

## 7. 发布与回滚（独立于 iOS）

- **版本管理**：独立 Bridge extension / service / protocol 三组版本，发布说明记录对应兼容矩阵；GitHub 独立 release 与验证过的 MV3 ZIP / checksum（不含运行态 data/secrets），Windows Service 安装/升级脚本，精确测试 SHA。无签名/未验证的包不进入生产。
- **受控部署**：先隔离测试，再独立 repo PR+CI、原运行目录备份 ZIP；后台/浏览器空闲时沿已验证 self-reload（不关闭 Chrome、不卸载、不刷新当前页面），原生状态 sentinel + pc-socket health 验收；服务迁移单写入者原子切换。
- **回退原则**：在命令/授权事务安全点回退；将前一个已验证 bridge service 与扩展发布组合恢复，恢复前合并两侧所有 commandId reservation/tombstones，保持当前配对 key + 旧命令结果，避免请求重放；`3211` 只保留一个 owner。若某条命令结果未知，先只读核查回执/人工确认，不能在回退时自动补发。
- **最终稳定性**：独立服务的系统启动/意外退出恢复、断网、手机切后台、Chrome 进程重启、Orchestrator 被停、bridge service 崩溃分别测试；单项故障不能误判为用户消息发送成功。
- **不改变** 已有 NPM host15、WireGuard、AliDNS、证书、主机 `192.168.233.127` 和同一个受限对外 API 地址；除非后续另有实际技术证据与单独批准。

## 8. 下一轮执行与 Handoff 记录

**权威规划文件**：此文（ChatGPT Web GitHub）；PC 本机另放 `D:\workspace\py\chatgpt-orchestrator\PC_BRIDGE_DECOUPLING_HANDOFF.md` 指向本文，以便旧运行维护路径查到迁移计划。**目前生产代码/配置权威仍在 Orchestrator**，只能在 M4/M6 真正验收并记录后切换权威位置。

**先读**：`chatgpt-web/AGENTS.md`、本文件、`IOS_070_NATIVE_UX_PARITY_HANDOFF.md`；PC `AGENTS.md`、`PC_DEPLOYMENT.json`、`PC_EXTENSION_HANDOFF.md`、`MOBILE_STRUCTURE_HANDOFF.md`、`MOBILE_CHANNEL_HANDOFF.md`、`IOS_PC_CLIENT_061_HANDOFF.md`。

**本轮已完成**：
- [x] 只读审查 Orchestrator/Chrome 扩展真实的 3210/3211/扩展模块边界与配对/journal 位置。
- [x] 新增分拆范围、候选新项目、接口契约、扩展 ID 稳定策略、M0–M6 开发顺序、测试发布与回退计划。
- [x] 联动 iOS v0.7.0 计划，并记录独立插件必须先验收后上线的门槛。
- [x] **文档更新而已**；未启动新服务、未切换 3211、未复制用户 data、未改现有生产扩展。

**后续待办（按时间追加完成证据，不能预先打钩）**：
- [ ] M0 最新 production read-only audit + 模块 import/IPC/消息枚举表 + 完整数据所有权图。
- [ ] M1 真正创建独立 GitHub 仓库和 mcpoffice 工作区，冻结候选命名，测试无 Orchestrator 的扩展载入。
- [ ] M2 独立 localhost Bridge service、state/journal 迁移工具、升级与回滚保护。
- [ ] M3 双向兼容契约 + 可选 Orchestrator adapter 和互斥租约的 Node/MV3 实证。
- [ ] M4 独立包/运行目录和 ID 保持或明确受控迁移方案，测试一套生产扩展与监听、恢复网络链路。
- [ ] M5 与 iOS v0.7 真机闭环（全历史的官方 UI 能力受证据约束）。
- [ ] M6 从 Orchestrator 完全移除扩展源码/3211 的构建与生命周期所有权，登记新的权威运行路径。
- [ ] 每次补充：时间、步骤状态、源码 GitHub SHA、新旧扩展 ID、3211 owner PID/路径、Key/journal 完整性结果（只输出校验状态，不输出值）、测试 run 数、发布版本/回退点、实际真机/Chrome 审计证据。

**停止条件**：扩展 ID 不能安全保留、命令防重无法无损迁移、Orchestrator workflow 健康变差、双监听/写入者、iOS 配对/真实 Send 回执不一致时，立即停止切换，维持/恢复上一稳定链路；绝不以删除浏览器数据、清空 journal 或重复发送来修复迁移。
