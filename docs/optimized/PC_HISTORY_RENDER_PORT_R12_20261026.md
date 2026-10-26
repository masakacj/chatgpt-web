# Optimizer R1.2 · PC Chrome 式长对话加载减负（2026-10-26）

**交付目标**：直接沿用 PC Chrome 扩展的低干预优化方向，提供原生策略开关和可回退的第一版历史布局减负，不重新开发一套优化/日志/状态管理架构。

## 移植事实

- PC 已使用的可靠部分：官方网页仍由 React 原生渲染；CM 事件驱动观察最新消息；不用永久全文轮询；不自动重试 POST/MCP；独立后台或外壳管理状态和监控。
- PC `long-chat-performance.js` 的分段原则参考：至少 24 个 turn、最新 12 个不处理、每次空闲处理不超过 16 条、route 切换清理。其 0.3.32 版本**并未作为正式优化启用**，所以这里只选择最小的 `content-visibility:auto` 实验，不直接移植当时未验证的 tool 折叠、MCP iframe 懒加载和 DOM 删除。
- 这不是完全绕开 WebContent 的渲染器。原生 App 持有 UserDefaults 策略和安全模式；页面侧仅在已有 CM `snapshot` 获取 turn 节点后做布局属性操作，不注册第二个 MutationObserver、长时轮询、网络拦截。

## 实现

- `OptimizedResources/Observation/pc-long-chat-adapter.js`：在隔离 WebKit content world 中运行，按需对历史 turn 加 `content-visibility:auto;contain-intrinsic-size:auto 650px`，取消时恢复原属性，永不删除网页节点。
- `conversation-observer.js`：沿用现有 CM `latest()` 的 `turns` 列表，不单独重新扫描；在运行中/待用户授权时不做新变更。
- `WebConfigurationFactory.swift`：加载 Adapter 早于 CM Observer；只有主框架，隔离 content world；Native UserDefaults 开关在新 WKWebView 创建时注入。
- `OptimizedRootView`：默认打开，可在诊断面板中关闭；提示“下次重建网页生效”。如果原生 Supervisor 安全模式开启则不注入优化能力。
- 不影响 `NativeResourceGate`。开启“资源过滤实验”仍是 0 条规则，与 PC 布局减负互不依赖。

## 验收测试

1. 不满 24 turn → 原样；满足 24 条 → 历史分批添加 CSS，最近 12 条 untouched。
2. 正在生成/等待审批 → 不做新修改；存在审批按钮的历史 turn 不处理。
3. 切换 conversation → 清理先前修改，过期 idleCallback 自动取消。
4. 关闭开关 → 无样式、无属性变更；destroy 还原。
5. 不创建第二个 CM 状态 owner，不加载第二个页面，不发送/重播 ChatGPT 请求，保留 Mirror Bundle ID 与独立签名。
6. 真机 A/B：在同一长对话中比较打开至最新消息可用、滚动位置和交互；需要进一步确认 `content-visibility` 在实际 iOS WebKit 的效果，不能用合成 Node 测试承诺省电。

**当前策略限制**：本方案可能降低屏幕外布局和绘制成本，但不会消除 React 堆内存或 iframe 中的 MCP 动画。效果取决于真实 WebKit 与 ChatGPT DOM；没有成功实机 A/B 前称作“实验候选”，而不是已验证加速。
