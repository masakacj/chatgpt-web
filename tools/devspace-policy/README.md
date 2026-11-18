# DevSpace Tool Policy R4 — 全节点一致化修复

本版仅修正 **`bash.command` 参数级说明**，消除与 v2 工具主体说明的冲突：

- 常规项目文件修改优先使用 `edit/write`。
- 用户明确授权的部署、服务维护、系统自有配置允许使用 Shell，需保留备份并验证。
- **不改动** MCP 执行器、认证、权限边界、端口、Operator Hook 或其他业务文件。

已在 Windows DevSpace 1.0.7 / 1.0.8、Linux DevSpace 1.0.8 上实测。R4 修复脚本严格匹配唯一一处说明，检查 Node 语法、同步原有 v2 manifest 的 `afterSha256`，使原版幂等检查及原始备份回滚保持有效。未知源码形态或哈希冲突拒绝写入。

## 一键安装 + 重启

Linux（Debian、mcp-officeserver，systemd）：

```bash
curl -fsSLo /tmp/devspace-policy-install-r4.sh 'https://raw.githubusercontent.com/masakacj/chatgpt-web/9b292ac5f0c5fa3eb07a7f362fe9b324f8323e7e/tools/devspace-policy/install.sh' && printf '%s  %s\n' 'f4c7298778038e5b1a4ce435af2f3a3e8d0625d1700555e652407adbedc60116' '/tmp/devspace-policy-install-r4.sh' | sha256sum -c - && bash /tmp/devspace-policy-install-r4.sh apply
```

Windows（mcpoffice、mcphome，管理员 PowerShell）：

```powershell
$p=Join-Path $env:TEMP 'devspace-policy-install-r4.ps1'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/masakacj/chatgpt-web/a57a9a81d5933ddbb112f2e98760f49474cc07e8/tools/devspace-policy/install.ps1' -OutFile $p; if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'e6de12fec5d434d5c79195327f7ae5a8b14c0165f7fc06e50047a9330fcf4f07') { throw 'Installer SHA-256 mismatch' }; & $p -Action apply
```

**Windows**：使用已部署的 `DevSpace Managed` 任务，延迟启动独立的计划任务验证旧进程后重启，并核对新 PID、7878 端口及 `/healthz`。失败时可经源文件和 manifest 哈希校验后尝试回滚原始策略。不会结束其他 Node 进程。

**Linux**：使用 `systemd-run` 安排 `devspace.service` 延迟重启并运行现有 rollback watchdog。Node 使用 `command -v node` 而非硬编码路径，兼容 `/usr/bin/node` 与 `/usr/local/bin/node`。

## 检查与回滚

- Linux：`bash /tmp/devspace-policy-install-r4.sh check`、`status`、`rollback`；安装脚本备份存放于 `/var/backups/devspace-tool-policy`。
- Windows：`& $p -Action check`、`& $p -Action status`、`& $p -Action rollback`；安装策略记录位于 `C:\ProgramData\DevSpaceToolPolicy`。
- Windows 可使用 `& $p -Action apply -NoRestart` 只更新文件，便于维护窗口内再重启。
- R4 是重复可执行的：若已修复，返回 `alreadyApplied:true`，不会再次改写源码。

本项目使用不可变的 Git commit URL 与下载文件 SHA-256 双重校验。工具说明需要在 **ChatGPT 界面手动点击「刷新工具」** 才能同步到已有对话，远端服务重启本身不会刷新客户端的工具元数据。

## 文件校验信息

| 文件 | SHA-256 |
| --- | --- |
| Linux `install.sh` | `f4c7298778038e5b1a4ce435af2f3a3e8d0625d1700555e652407adbedc60116` |
| Windows `install.ps1` | `e6de12fec5d434d5c79195327f7ae5a8b14c0165f7fc06e50047a9330fcf4f07` |
| 参数修复 `fix-bash-parameter.mjs` | `f2ebb1b83358d8e3eadbaaa6267b35420a2735a2b5089236ed376563c39a9960` |
| 原 v2 策略压缩包 `devspace-tool-policy.mjs.gz` | `22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8` |
| Windows 托管重启助手 `restart-managed.ps1` | `5d7424c2963b22e9714143dbd0e7b1d8c67e332a10c9f49f7ffb8367cedf713a` |

## 已验收节点

| MCP | DevSpace | 服务/端口 | 结果 |
| --- | --- | --- | --- |
| mcpoffice | 1.0.7 | Windows Managed / 7878 | PID 42572，healthz 200，manifest match |
| mcphome | 1.0.8 | Windows Managed / 7878 | PID 44484，healthz 200，重复安装幂等 |
| mcpdebian | 1.0.8 | systemd | PID 1259878，active，参数已修正 |
| mcp-officeserver | 1.0.8 | systemd | PID 154651，active，参数已修正 |

回滚逻辑保留，但未对生产服务刻意执行故障注入测试。mcp-officeserver 上的 sudo 主机名解析警告为原有配置问题，不影响本次运行。
