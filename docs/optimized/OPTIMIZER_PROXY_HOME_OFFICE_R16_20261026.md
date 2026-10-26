# Optimizer 0.1.6 · App-Scoped Proxy · 2026-10-26

Scope: **ChatGPT Web Optimized only**. Base reviewed branch `ea0b3f75c256400309a6be11bbfd806f0327f1e8`. Ponytail Full. Original user configuration: **Home main / Office GOST backup enabled / forbid auto direct**.

## Actual environment inventory

- Office proxy `127.0.0.1:7890` is local Clash Verge/mihomo; not accessible to iPhone and must not be published unauthenticated.
- Office `10.0.92.89:13214` is Bridge-specific gateway; it is **NOT an HTTP CONNECT proxy**.
- Existing Home↔Office GOST route is known for Bridge but does not establish a public TLS CONNECT proxy for WKWebView. Home Debian `192.168.233.137` had no verified open HTTP CONNECT listener in the read-only scan. **No hostname, TLS cert or authenticated public CONNECT port was provided.**
- Therefore no proxy host/port has been invented or hardcoded. The App is fail-closed until the user supplies verified authenticated Home and Office HTTPS CONNECT endpoint details. Deployment of the two new server endpoints remains a separate networking work item; does not involve changing Bridge 13213/13214, WG/Parsec or Home WAN 443.

## Native implementation

`OptimizerProxySettings` (Optimizer-only UserDefaults + Keychain) owns the configured endpoint order and credentials.
`WKWebsiteDataStore.default().proxyConfigurations` is applied before constructing the only Optimized WKWebView's first request. Two `ProxyConfiguration(httpCONNECTProxy:tlsOptions:)` values in Home/Office order, each `allowFailover=false` (no nonproxied fallback). TLS is mandatory; credentials saved in the Optimized App Keychain with device-only accessibility. Normal WebView data store is unchanged so existing login can survive, but proxy updates apply only to Optimizer (separate bundle, no app group). The optional existing Cloudflare URLSession telemetry is NOT within the WebKit proxy data store.

Initial plan is Home, Office backup ON, forbid auto direct ON. When endpoints are missing or a username has no Keychain password, native settings is shown and NO ChatGPT request is sent. The explicitly named `手动直连` mode is a separate user-selected mode; never selected by fallback or failure. Native settings can only save with explicit confirmation while no running/waiting task is known. All production proxy settings owners share a **MainActor process-wide routing lock and process-wide active plan**, preventing a second WindowGroup scene from reconfiguring the default WebKit store. Later saves update persistent UserDefaults but do not replace the active routing plan or reconfigure the shared `WKWebsiteDataStore.default()` even if the WebView is rebuilt from native safe mode. The saved change takes effect only on a full App process restart. Password changes made after a WebView's first proxy configuration are written to separate `pending-home` and `pending-office` Keychain accounts, never replacing credentials of the currently active route. At the first native App startup per process (once even with multiple scenes), pending secrets are promoted to the active Keychain accounts *before* WKWebsiteDataStore is configured; an in-process change cannot change the old route's credentials. If no WebView was ever created (fresh fail-closed setup), first configured load can proceed. Never switch an in-flight request.

Home then Office are supplied as an ordered WebKit proxy configuration list. Each `allowFailover=false` explicitly rejects fallback to **nonproxied** connections. There is no App-driven reload or POST replay on provisional navigation errors: an unreachable proxy causes a native error and does not switch the old WebView's shared data store. Whether WebKit actually uses the second proxy when the first is unreachable requires physical-device testing against two verified HTTPS CONNECT endpoints; backup must not be reported as E2E-passed before that test.

## Server-side deployment (not yet implemented / verified)

1. Deploy an **independent authenticated TLS HTTP CONNECT** listener on Home with CA-trusted cert + credentials and outbound home residential egress. Do not reuse management/WAN-443 endpoints or set a public open proxy.
2. Deploy a separate authenticated TLS CONNECT listener for Office egress over the existing GOST route. Keep Bridge/IPA services and GOST jump untouched.
3. Validate TLS chain/SNI, proxy auth rejection (407), approved auth 200 CONNECT, source egress IP, ChatGPT HTTPS, long SSE/streaming, MCP WebSockets, 5 MB upload and idle timeout. Tests should be made from an external network, not merely LAN.
4. Enter only the verified names/ports/credentials into the iPhone settings (passwords into Keychain). Recheck Home failover to Office with a safe initial GET. Record no chat Send during automation.

## QA / release boundaries

- Simulator tests: missing endpoints -> native blocked state (not web view); explicit direct test fixture only; persisted Home/Office order; malformed host/port rejected; no secret in defaults; native proxy configs `allowFailover=false`; backup single-shot.
- Keep existing Native Supervisor/circuit and long-chat history adapter tests; no Mirror edits.
- GitHub macOS iOS 17+ tests and Release compile, separate candidate signing, IPA signature/hash and installer HTTP verification.
- No claims of working Home/Office egress or true failover until **actual TLS CONNECT server endpoints** exist and iPhone A/B confirms. Signed IPA is candidate-only, no Optimized stable promotion or Mirror latest change.
