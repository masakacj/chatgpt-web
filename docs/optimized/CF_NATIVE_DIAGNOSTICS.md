# Web 优化版：iOS 原生日志（CF/D1）

状态：候选版 0.1.2 (3) 的源码实现，正式真机验收前不得称为稳定版。

## 选型

- 主通道：复用现有 Cloudflare Worker `chatgpt-web-telemetry`，HTTPS `/v1/telemetry`，沿用 D1 `perf_samples`（schema 1）；本阶段**不改 Worker / D1 schema**，也不碰已冻结的镜像版代码。
- 深度排查：iPhone 的 iOS 分析数据（JetsamEvent / WebKit 进程崩溃报告）或连接 Mac/Xcode 抓取系统日志。mcpoffice 可收集网络和 App 自己上报的信息，但 Windows 单纯连接 iPhone 并不能直接获得 Xcode 完整的 WebKit/Jetsam 诊断。
- iPhone 不需要和 mcpoffice 在同一个 LAN，也不需要开放任何家用端口。

## 采集点

所有网络上传由 `OptimizedApp/Diagnostics/OptimizedTelemetry.swift`（Swift 原生代码）负责，WebContent 不会执行采集网络请求。

| reason | 触发 |
|---|---|
| `launch`, `foreground`, `background` | App 生命周期 |
| `nav_start`, `nav_finish`, `nav_error` | WKNavigationDelegate（错误只采集数字代码，正常 -999 取消不记错误） |
| `web_terminated` | `webViewWebContentProcessDidTerminate` |
| `auto_recovery`, `recovery_paused`, `manual_recovery` | 恢复动作和熔断 |
| `memory_warning` | iOS 发给 App 的内存警告通知（注意不等价于 WebContent 的 Jetsam） |
| `download_error` | WKDownloadDelegate 返回下载错误 |
| `heartbeat` | App 前台最长每约 120 秒一次 |

- `mode=ios-optimized`，`reason` 为上述事件，`route_kind` 只允许 `home/conversation/project/other`，可附加 `_e<整数错误码>`。
- `debug_id` 是无意义事件编号，`install_id` 是随机安装标识，`session_id` 是每次运行新建的随机会话编号；都不含账号信息。
- `uptime_ms` 为 App 本次启动以来的相对毫秒数。事件可能在网络恢复后才入库，`received_at` 是 D1 **服务器收到**的时刻，不一定是事件发生的时刻。
- 不保存 URL（包括完整对话/项目路径）、DOM、聊天内容、输入框、网络请求和响应正文、Cookie、Token、位置、IP。Worker 自身仍可能按 Cloudflare 平台策略处理连接元数据。
- 事件队列本地最多 80 条，单次最多 12 条，失败指数退避至 5 分钟；在 App 被杀或断网后保存待发事件，下次启动重试。
- 原生诊断界面可关闭采集、查看会话编号/上传状态/队列量、手动重试、分享本地摘要。关闭后清空本地待上传队列（不删除 D1 既有记录）。

## 读取近期事件

在已授权的 Wrangler 环境（请勿放任何 CF 凭据在这个公开仓库）：

```bash
npx wrangler d1 execute chatgpt-web-telemetry --remote --command="SELECT datetime(received_at/1000,'unixepoch') AS received_utc,session_id,reason,route_kind,uptime_ms,app_version FROM perf_samples WHERE mode='ios-optimized' ORDER BY id DESC LIMIT 100"
```

只看特定会话时，在查询中加上 `AND session_id = '<诊断页的会话编号>'`；避免公开上传此查询结果中的随机标识。

## 注意事项

此方案定位**频率、时间顺序、路由类别、系统回调是否发生、自动恢复是否循环**。它不能直接证明 WKWebView 进程因内存不足终止，也不具备符号化崩溃堆栈；如果某次终止发生在整个 App 也被系统杀死的情况下，最后一条事件可能无法及时发送，应配合 iOS 分析报告。发布仍受优化版真机验收门槛约束。

CF 健康接口：`https://chatgpt-web-telemetry.masakacj.workers.dev/health`；2026-10-13，测试事件请求返回 HTTP 202 / accepted=1。
