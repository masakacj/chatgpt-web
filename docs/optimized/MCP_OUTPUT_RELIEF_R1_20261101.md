# MCP-OUTPUT-RELIEF-R1 — PC Optimizer + iOS Web Optimized 专项代码合同

2026-11-01。用户最新要求：开始修改优化，优先屏蔽 MCP 工具调用产生的大量输出；用户消息、普通助手文本、最终回答完整保留，尤其不能等到模型完成思考才显示。iOS App 需同步改造。沿用 2026-10-31 双端合同的 AGY Developer / CC Independent Reviewer / AGY Repairer 与 Ponytail FULL；只交付真实功能与真实测试证据，不承诺虚假性能改善。

## 源码基线与保护面
- PC Chrome 当前正式扩展 0.1.0，源码 D:/workspace/py/chatgpt-pc-optimizer。已有 content.js 历史消息 content-visibility:auto、24/12 原则与 MutationObserver；复用这个观察器，避免另造扩展/后台代理。修改限同一扩展的 JS/Popup/相关本地测试；默认 MCP 功能关闭，允许立即通过 Popup 开关，原历史开关保持独立。
- iOS Web Optimized 来源 0.1.9 源代码 SHA a3a3c7eac9c812b4f0df67bd896efbb2cb82b22e，完全干净 worktree C:/Users/Administrator/.devspace/worktrees/chatgpt-web-8dca1163。原有单一 CM 观察器每次刷新调用 pc-long-chat-adapter.js 的 refresh(id,turns,activity)。复用这个刷新以及原 WKContentWorld 注入通道，不另加全局扫描定时器 / MutationObserver / JS 注入代理。iOS Optimize 添加原生设置 MCP 输出减负开关（默认关闭，需重建 WKWebView 才生效，必须明确说明），注入布尔控制到当前 adapter。严格只修改 OptimizedApp/、OptimizedResources/Observation/、Optimized test 和 target-only版本字段，不能碰镜像 App/、Bridge、签名中心和现有 Keychain/代理安全。
- 前次 AGY 双端 0.2.0 开发未完成正式审核/发布；PC 正式仍是 0.1.0，iOS 线上另有 0.1.9 Build 11 候选。不合并此前未审查的 0.2.0 目录，不倒退签名版本。此次只做 MCP 输出专项，不改 DNR/WebKit 原生资源白名单，不劫持 HTTPS、官方对话 JSON 或 Send。
- Ponytail Full：最小完整 diff、复用既有代码与平台 API；没有新服务/依赖/抽象框架；不删必要安全/测试；不重写整个 WebView。

## 功能要求（必须同时落实）
**M1 区分内容、保留正文**：只命中明确标记的工具结果正文容器，例如 data-testid 中的 tool-result/tool-output/tool-response/mcp-result/mcp-output 等，与 ConversationManager 已知的活动/工具容器结构。用户/助手普通 Markdown、最后输出、工具错误概述、思考流程标签都不能被误判；用户文本中出现 MCP/tool 字样仍应显示。未知 DOM 必须保持原样。

**M2 在生成过程中减负**：对于匹配明确工具输出容器，按实测阈值 >= 1KB 或适量 > 100 元素才减负，使用 CSS display:none/content-visibility:hidden 或类似原生 CSS，不能移除整个对话 turn。优先在工具执行中的快照刷新阶段处理，不等模型思考完成。保留状态、工具名称、进度与用户确认/授权控件。任何包含按钮、a[href]、textarea、select、iframe、role=dialog、MCP App 交互控件的目标或直接祖先保守放行。避免强制全文扫描、反复 getBoundingClientRect 触发布局。

**M3 完成后减负与恢复**：无授权、无互动控件的已完成旧工具输出继续隐藏；能够可逆关闭，立即恢复所有自身属性/CSS，不刷新页面、不重新请求官方接口。禁止 DOM replaceChildren/textContent='' 删除 React 管理的子树，因为已有实际客户端依赖和恢复风险。当前对话结束只保留可见的工具名称/状态，长输出正文不绘制。网络原始数据仍会到达，不得声称节省了 JSON 下载/React JS 解析内存。

**M4 不争用生成中布局**：PC 既有历史内容高度测量在当前 assistant streaming/running/waiting_user 时不得执行新的布局测量（已有旧 frozen CSS 状态可留存，待空闲再处理）。iOS 既有 long-chat adapter 已有 running/waiting 闸门继续保留；MCP 输出裁剪独立于旧历史12条优化，正在生成的普通文本始终可见。切换对话 reset、关闭开关立刻还原；动态新输出也能被后续 CM/Mutation 观察器发现。

**M5 控制与指标**：PC Popup 独立「MCP 工具输出减负」开关/本地已处理输出数量，与长对话历史开关彼此无关。iOS 诊断增加「MCP 工具输出减负」独立 Toggle 与简洁说明：「下次新建网页生效，保存的登录和代理设置不变」；不要在切换时自动重建网页（会丢草稿）。若能复用现有状态采样，报告本地处理数；不保存工具正文/密钥。云端运行和云端API请求数必须不增加。

**M6 全量测试**：基于离线合成 DOM、只读 fixtures 验证巨大 MCP 工具正文被隐藏，显示状态/按钮，普通 Markdown 与用户文本完全保持；当前生成中生效；小工具内容不乱隐藏；等待授权、异常、MCP iframe 交互免疫；OFF 可逆且旧历史 CSS 正常；切换路由清理；连续 Mutation 不进行 O(n²) 全对话扫描。PC node --test + Playwright 隔离 Chromium（无官方 API）；iOS Node vm adapter test + scripts/check-target-boundaries.mjs + check-cm-contract.mjs，macOS Xcode/XCTest 交给可信 CI；没有真机证据时不能宣称已完成实机验收。

## 角色、验收与交付
AGY 使用 Gemini-only 8045 验证模型路由，在隔离 Stage 代码，两个候选各自有 changed path SHA、没有 outsideOwned。Host 独立本地测试，再 CC GPT-6 独立高阶 Review 检查 M1–M6、源码/测试、潜在破坏 ChatGPT React、真实隔离测试，CHANGES_REQUESTED 发 AGY 新修复工单。仅通过 Reviewer 和 QA 的候选可以部署。PC 要保留原扩展 ID/备份与可回滚状态；iOS 最新 signed candidate 独立 Build 12 或以后核验，必须 macOS 编译、签名与安装验收后标可体验。失败不能宣称 success。
