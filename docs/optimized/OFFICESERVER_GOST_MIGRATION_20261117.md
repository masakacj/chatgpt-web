# Optimizer OfficeServer GOST 切换记录（2026-11-17）

## 目标与安全边界
- 新客户端主出口：OfficeServer GOST，专用域名 `gostos.781751.xyz`，TCP 18445，受信任的 TLS 与独立 GOST HTTP CONNECT Basic 认证
- 备用：原 Office GOST，保持单独运行，原地址与 Keychain 凭据按 v1→v2 迁移
- 删除 Optimizer 运行时 Home 选项及 Home 回退，不清理旧 v1 配置/凭据，便于明确回滚
- 无自动直连、无请求重放，不修改 Mirror app 或其他 GOST

## 当前链路
```
iOS Optimizer -- CONNECT over TLS --> gostos.781751.xyz:18445
     公司边界路由需将公网 TCP 18445 转发到 10.0.101.48:18445
OfficeServer 10.0.101.48:18445 -- TLS frontend -->
127.0.0.1:18545 -- GOST HTTP CONNECT (Basic auth) --> Internet
```

## 已验证
- DNS：AliDNS `gostos.781751.xyz A 59.60.0.178`，TTL600；这是当前观测的公网出口地址，可能会变化
- OfficeServer GOST `gost-optimizer-connect.service`：enabled+active，仅监听 `127.0.0.1:18545`
- TLS 前端 `gost-optimizer-tls-gateway.service`：enabled+active，监听 `0.0.0.0:18445`，转发到本机 GOST
- 有效公网信任证书：`gostos.781751.xyz`，Let's Encrypt，2027-02-15 到期；私钥仅保存在 OfficeServer，权限 0600
- 本机无凭据 HTTPS CONNECT → 407；正确凭据 → 200；TLS 验证通过
- 从外部访问 `59.60.0.178:18445` 的 TCP 连接未能完成 TLS 握手；**未验证公网入站可用**
- Office GOST 原服务未修改；独立备用公网端口需要另行验证

## 待公司边界网络完成
1. 验证 `59.60.0.178` 是否为该公司可入站且可控制的公网 IP。若只是共享 NAT/出口地址，需由网管提供可用入站映射或采用专用中继；单改 DNS 无效。
2. 配置 TCP 端口转发：公网 `18445` → `10.0.101.48:18445`，并按公司策略做源地址/防火墙限制；不能把明文内网 `18545` 转发到公网。
3. 从不在公司 LAN 的设备验证 TLS SNI `gostos.781751.xyz`，不带认证应返回 407；使用安全录入的独立 OfficeServer 口令应能 CONNECT 成功。
4. 核实既有 Office 备用可从 iPhone 访问，否则应临时关闭备用开关而不是重加 Home。
5. 才能更新新 App 用户端配置、完成物理 iPhone QA，再进入签名候选/正式部署。当前 feature 分支禁止直接升 stable。

## 客户端分支
`feature/optimizer-officeserver-gost-20261117`
- `OptimizerProxyMode` 仅包含 `officeServer`、`office`、显式 `direct`
- v2 Plan 不包含 Home，v1 Home 记录只用于解析并保留旧值，绝不作为新代理出口
- Keychain `officeServer` 与 `office` 独立；新 OfficeServer 密码不可复用旧 Home 密码
- 既有功能/流畅度相关改动保持不变

## 续期与回滚
- CSR 对应 OfficeServer 唯一本机私钥。CSR 签证可从 Debian 使用 AliDNS DNS-01 自动挑战，获得公开 fullchain 后转交 OfficeServer。
- CSR 模式证书**不会自动续期**，务必在 2027-02-15 前续期、验证 TLS 链并重启专用 TLS service。
- OfficeServer 仅停用新服务：`sudo systemctl disable --now gost-optimizer-tls-gateway gost-optimizer-connect`；不会修改原 Office GOST。
- 客户端回滚到旧正式版时，仍保留旧版 v1 配置；新 app 分支和主版之间不互相迁移 Home 出口。
