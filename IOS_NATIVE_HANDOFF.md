# iOS native parity handoff — 2026-10-10

This task is explicitly authorized by the user's NEW iOS request. It does not change the PC extension. Read PC_EXTENSION_HANDOFF.md for desktop; do not revive Tampermonkey or apply iOS findings to PC.

## Version and scope

Candidate app/shared menu version: **0.4.44**. Native conversation module: **1.0.0**. Base stable source was main commit f9b792a41142a064e71494b728a36c345361e145 (iOS app 0.4.43; PC retirement guards already present). Integrated code tested at e369463e30f2ecacb6f8239ec484c29b13731bcf.

The source remains in GitHub. No iOS source checkout or IPA was written to MCP machines. The existing mcpoffice WebKit Twin is only a test harness, fetching pinned source into memory. The one-time exact integration ran and committed in an isolated GitHub Actions branch; it fails on unexpected base source and is idempotent after integration.

## What maps from PC to iOS

- PC chrome.storage.local -> native **UserDefaults**, key ChatGPTWeb.nativeConversationResilience.v1. State is independent of website localStorage and the WKWebView process, with 30-day/300-record retention.
- Existing website status records are imported into native storage. No site storage, cookies, IndexedDB or caches are cleared.
- Current native turn running/waiting/complete + actual assistant text are the evidence. Empty or failed hydration never overwrites a previously confirmed result. Stale running/waiting after 90 seconds displays 待同步. Browser/App closure does not give real-time knowledge of server completion.
- Native WKContentWorld bridge is separated from page JavaScript. Origin, main frame, current WKWebView, document token, and current conversation ID are checked by Swift. Only IDs/enums/timestamps/structural booleans cross the bridge; no chat body, token, cookies or request headers.
- One sidebar observer and one direct current-turn/list observer; no whole-transcript subtree observation, no permanent idle interval. Finite startup checks and a temporary active-run timer mirror PC logic.
- KVO on the existing WKWebView URL/loading and foreground notification reattach/refresh the state layer for SPA navigation and WebKit reload. Existing navigation delegate, login/session, no-gesture shell, native floating button, script hot update and diagnostics remain.
- New native parity bootstrap prevents the old menu resource from restarting its historical Result Only pruning or duplicate state processing. The original historical MCP DOM and final answers are not removed. This matches PC's minimal native-display approach, but retaining more original history may cost more memory on iOS; physical-device validation remains essential.

## IMPORTANT: loading retries are not fully equivalent

The native pure policy implements PC's two attempts/five minutes, durable budget, current-document/route checks and draft/generation/approval protection, and those rules are tested. **Automatic saved-conversation retries are NOT enabled in this iOS build**, because this implementation has no reliable public equivalent of Chrome webRequest providing authenticated read-failure metadata.

No fetch/XHR wrapper or interception is installed. No extra API request, credential copy, request-body inspection, prompt replay or automatic page reload is added. The recover operation explicitly returns retryAfter=-1 / native_read_evidence_unavailable. Unclassified network errors are not assumed transient. The existing native Retry UI remains available to the user.

Do NOT claim every PC retry mechanism was copied, or that random loading failures are fixed. UI error alone is not enough to safely identify a retryable saved-read failure. Future work must get trustworthy supported-platform evidence first, or keep the conservative fallback.

## Files

- App/ConversationResilienceStore.swift — native state, migration, TTL and retry policy.
- App/ConversationResilienceBridge.swift — weak WKScriptMessageHandlerWithReply, isolated content world, WKWebView lifecycle, fail-closed recovery.
- Resources/NativeConversationBootstrap.js — native ownership/document marker only; no network hooks.
- Resources/NativeConversationClient.js — tiny view adapter, state evidence and native bridge. Not a Tampermonkey entrypoint.
- App/ChatGPTWebView.swift — attach same native controller and preserve scripts across hot-update reset; existing delegate remains.
- safari/chatgpt-safari.user.js — v0.4.44 menu/hot-update compatibility. The native parity flag disables duplicate pruning/state logic ONLY in new native containers. Older iOS containers retain their previous path.

## Validation evidence

GitHub Actions Native iOS Parity Prepare run **38054324379** passed exact integration, npm runtime checks, compiled native Foundation/UserDefaults safety tests and the actual iOS device target build. Both bundled resource files were confirmed in the built .app. No signature from this preparatory build is implied.

Compiled Swift policy tests cover persisted running/completed state through store recreation, stale uncertainty, old-route rejection, failed hydration preservation, new-send/old-answer protection, legacy import, draft/approval/generation protections, and budget persistence across restart.

mcpoffice `D:\workspace\py\chatgpt-ios-twin\test_native_parity_044.py <pinned SHA>` passed seven WebKit scenarios: 96 MCP iframe/final-answer preservation; delayed sidebar; native state change after 66 seconds idle; background/foreground and settings toggles not reviving pruning; page-close/reopen state restoration; unloaded new route not falsely completed; unknown-error no-retry with draft preservation. The WebKit native bridge is mocked in these fixtures; the actual Swift store is tested separately. This is NOT physical-iPhone acceptance or a live ChatGPT benchmark.

## Kernel decision

Keep WKWebView. Chromium's supported iOS web layer wraps WKWebView; changing the browser brand/User-Agent/container is not replacing WebKit with desktop Blink/V8. Apple's alternative-engine programs require special approval, entitlements, region/version eligibility and ongoing engine security maintenance (EU and Japan rules differ). A normal self-signing certificate is not that authorization. No Blink engine, JIT entitlement, jailbreak, or undocumented WebKit API is added.

## Release / rollback

Use the existing iOS IPA workflow and signing center; verify the exact app version/build/latest manifest after publish, not merely GitHub source changes. Update in place, do not uninstall or clear website data. Keep previous v0.4.43 signed build as a rollback candidate (signing validity must be verified if reused).

Rollback code is the parent/base ref above. Revert only the iOS native parity integration, resources and shared-menu version as needed; retain the PC retirement guards. Do not restore PC userscripts. Native state is a new namespaced record and does not require deleting site data on rollback.

Remaining: physical iPhone startup/side-panel speed, actual WebKit restart persistence, and long-conversation memory pressure must be measured. This is functional logic alignment and native-state hardening, not a guarantee of desktop-equivalent performance or a completed independent native answer reader.


## 2026-10-10 晚间：偶发对话白屏与原生悬浮按钮无响应

用户在 iOS 0.4.44 报告：偶有对话正文白屏，其他网页组件仍显示；右上角原生 S 按钮点击后没有展开菜单。当前 iOS 容器仍使用 WKWebView，不是 Blink Chrome。**切勿因此更新 PC 扩展或恢复油猴脚本。**

### 已证实的线索与边界

- 在线隐私最小诊断在台湾时间 2026-10-10 **22:51:52** 报告 `ios_web_terminated`：WebKit 网页内容进程发生终止。时间与用户反馈接近，但不代表每次白屏都是同一原因。
- 旧原生 `ChatGPTFloatingAnchorButton` 收到 tap 后实际通过 `WKWebView.evaluateJavaScript()` 打开网页里的菜单，旧版失败时连续重试最多12次，主网页脚本无响应时原生按钮看起来像失效。
- 用户网页会话正文没有被此问题证据证明丢失；此轮不得删除对话历史、清除 Cookie/IndexedDB、禁用 MCP 授权，或调用后台 ChatGPT POST/retry。
- WebKit 自身已有 WebContent 终止后**最多一次/180秒**的自动页面重载保护，未在本轮提高重试次数。

### 本轮修复

独立分支 `fix/ios-native-panel-fallback-20261010`：

1. 原生 S 按钮 tap 时立刻触觉反馈，原有网页功能菜单正常时仍优先使用。
2. 若网页 JS 在1.6秒内未响应，或在等待时再次点击，立刻显示由 **UIKit UIAlertController** 构建的本机应急菜单，不依赖 WebKit JS：原生后退、返回ChatGPT首页，以及**二次确认后**手动重新加载。取消与等待均不刷新，不清除登录，不重发消息。
3. 原有网页菜单注入失败时尝试次数从12缩减到3；异步回调按请求序号核对，导航/回退/原生应急菜单启动后旧回调不再能错误标记菜单准备完成。
4. 原生 `ChatGPTNativePerformanceProbe` 新增仅在既有用户同意诊断的情况下报告 `ios_panel_js_timeout` 元信息，不采集聊天正文、URL、会话标识或请求体。没有新增自动轮询或ChatGPT API网络请求。
5. 原生 UI 回归新增 `--ui-testing --ui-panel-stall`，故意让**测试用** WebKit 菜单调用不返回，验收按钮在不依赖 JS 的情况下弹出 UIKit 应急菜单，并检查手动刷新必须二次确认；此旗标只在测试运行有效。
6. **IPA 应用/脚本营销版本保持 v0.4.44**，因为只修改 Swift 原生容器，不触发用户脚本热更重新注入；发布 Build 号由 GitHub CI 自增。签名前须先通过隔离分支上独立 macOS iPhone Simulator UI 测试。

### Handoff 与回退

- 代码：`App/ChatGPTWebView.swift`、`App/NativePerformanceProbe.swift`、`UITests/ChatGPTWebUITests.swift`；隔离测试 `.github/workflows/ios-panel-recovery-test.yml`。
- 正式版本在合并前保留已签名 `0.4.44 (217)`；未经隔离 UI gate 通过不得声称修复已经发布。
- 成功后验收 IPA 安装中心 `https://ipa.78175132.xyz/api/v1/apps/chatgpt-web/latest` 的准确Build、签名和manifest可用性；**直接覆盖安装**，不卸载、不清数据。
- 如果出现回归，回退此分支引入的 Swift 原生菜单/测试代码即可；历史会话本地状态属于现有原生 UserDefaults，不应被删除。
- 该修复保证**卡住的JS不能让原生菜单一起失效**（只要iOS主线程仍响应），并提供可控恢复入口；不意味着长对话白屏/内存压力的根因已消除，须用真机日志复测是否有后续 `ios_web_terminated`。


### 发布与验证回执（2026-10-10 台湾时间 23:22）

- 用户报告的旧版：iOS 0.4.44 Build 217。云端自愿诊断 22:39 和 22:51 两次 `ios_web_terminated`，与偶发白屏接近；说明该版本存在真实 WebKit 进程终止，但不能宣称所有白屏皆由它触发。
- 合并：PR #52，main commit `cca2b3d464bca52216f8bc8cceae13eeb9e7e8d9`，没有改变 PC 扩展/旧退役脚本、WKWebView 内核或用户登录数据。
- 修复：正常网页悬浮面板保留；JS等待1.6秒无答复或再次点击即出现 UIKit 原生应急菜单。旧网页JS注入重试上限从12降至3，并以请求序号丢弃过期回调。原生用户主动选择后退/首页；手动刷新必需二次确认，保护未发送草稿。不增加任何 ChatGPT API 自动重试/整页刷新。
- 限制：本补丁为 **native UI escape hatch**，并不修复 WebKit 内容进程被终止的底层内存/React加载原因。iOS主线程本身如果也卡死，UIKit菜单同样不一定能显示；此时需手动关闭后重开 App。
- 诊断：既有 opt-in 数据链路只在应急菜单触发时上报 `ios_panel_js_timeout`，只包含有限元数据，不包含 URL/会话ID/正文/Token。
- 独立 CI：GitHub Actions `38062282710` **success**；Release设备编译成功、Swift UserDefaults原生持久化30个断言通过、真实iPhone模拟器 `testNativeFloatingFallbackWhenWebKitStopsAnswering` **passed (69.488s)** 和 `testWKWebViewResultOnlyStress` **passed (22.687s)**，2 tests / 0 failures。
- 正式发布：GitHub Actions `38063243294` 的 **build-ipa 已success**，签名及安装中心上传成功；修复版沿用营销版本 **0.4.44**，自增 Build **218**。发布API `https://ipa.78175132.xyz/api/v1/apps/chatgpt-web/latest` 已核实为 Build 218；安装清单 `https://ipa.78175132.xyz/manifest/232ed97f-b934-4150-9698-aee66b7fc048.plist` HTTP 200；安装中心主页 HTTP 200。正式 ui-smoke 独立 Job 尚在运行时记录，不能凭它宣称总体 workflow PASS。
- 覆盖安装即可，不需卸载、清缓存或重新登录。旧 Build 217 已签名包作为回退参考；若用户真机依然频繁白屏，请对照 `ios_web_terminated`、`ios_nav_fail`、`ios_panel_js_timeout` 时间戳，继续按真实进程内存压力调查，**不要重启历史 JS 剪枝/拦截 iframe 实验**。
