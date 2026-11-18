# DevSpace MCP Tool Policy — R3 多机一键安装与重启

适用 `@waishnav/devspace` 1.0.7 / 1.0.8，已在以下节点实测：

| MCP 节点 | 系统 | 服务管理器 | 策略应用 |
| --- | --- | --- | --- |
| mcpoffice | Windows | DevSpace Managed 计划任务 | R2 已安装；R3 可重启 |
| mcphome | Windows | DevSpace Managed 计划任务 | R3 安装 + 自动重启已通过 |
| mcpdebian | Debian/Linux | systemd devspace.service | R2 安装 + R3 重复执行自动重启已通过 |
| mcp-officeserver | Debian/Linux | systemd devspace.service | R2 安装 + 自动重启已通过 |

脚本只更改 MCP 的工具使用说明，不更改实际权限、认证、执行器、业务数据或端口。不能绕过 ChatGPT 的安全策略。已经安装的策略会进行源文件哈希比对，拒绝覆盖其他更新。原文件有校验备份。

## Linux 一键安装（已验证 SHA-256）

```bash
curl -fsSLo /tmp/devspace-policy-install-r3.sh 'https://raw.githubusercontent.com/masakacj/chatgpt-web/db84ae782ffdd42b42421c3525ad3015abb523c8/tools/devspace-policy/install.sh' && printf '%s  %s\n' '8db00986f80535f304cd907e42a67de7d0d582f72c6a2d40ea0913659146d52a' '/tmp/devspace-policy-install-r3.sh' | sha256sum -c - && bash /tmp/devspace-policy-install-r3.sh apply
```

- 首次安装：策略安装器调用 systemd-run 安排稍后重启 `devspace.service`，并通过 watchdog 检查和必要时回滚。
- 重复执行：即使策略已存在，也会安排 `devspace.service` 延迟重启，确保文件已加载。
- 状态：`bash /tmp/devspace-policy-install-r3.sh status`（使用 sudo 查阅有权限保护的备份）。
- 回滚：`bash /tmp/devspace-policy-install-r3.sh rollback`。

## Windows 一键安装（管理员 PowerShell）

```powershell
$p=Join-Path $env:TEMP 'devspace-policy-install-r3.ps1'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/masakacj/chatgpt-web/fa01199a0760930e7246ba04c30df6b44e48caba/tools/devspace-policy/install.ps1' -OutFile $p; if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne '2030122ffe48f2ed9c40a3c4aa171198550778691539a26a1da6a2ed968ae365') { throw 'Installer hash mismatch' }; & $p -Action apply
```

如果安装器检测到 `DevSpace Managed` 计划任务：
1. 通过已验证的独立脚本建立 SYSTEM 一次性重启计划任务。
2. 等待当前安装命令退出后停止 DevSpace Managed，核对旧 PID、创建时间及 CLI 命令行，必要时只结束该 DevSpace 子进程。
3. 启动原 `DevSpace Managed` 任务，并通过 `/healthz` 和新 PID 验证。
4. 若无法恢复健康，源文件哈希与备份校验符合时才执行回滚和恢复，再记录结果。

**不重启其他 Node 进程，不修改登录凭据，不启用已禁用的旧任务**。不具备受支持的任务管理器时返回 `manual`，不擅自杀进程。重启任务为固定名称、可重复使用，日志在 `C:\ProgramData\DevSpaceToolPolicy\restart-status.json`。

- 检查：`& $p -Action check`。
- 状态（含最近一次重启记录）：`& $p -Action status`。
- 回滚：`& $p -Action rollback`。
- 仅补丁、不自动重启：`& $p -Action apply -NoRestart`。

## 发布文件校验

安装器和 helper 用固定 SHA-256 校验；策略压缩包引用不可变 Git commit：

| 文件 | SHA-256 |
| --- | --- |
| `install.sh` | `8db00986f80535f304cd907e42a67de7d0d582f72c6a2d40ea0913659146d52a` |
| `install.ps1` | `2030122ffe48f2ed9c40a3c4aa171198550778691539a26a1da6a2ed968ae365` |
| `restart-managed.ps1` | `5d7424c2963b22e9714143dbd0e7b1d8c67e332a10c9f49f7ffb8367cedf713a` |
| `devspace-tool-policy.mjs.gz` | `22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8` |
| 解压后 `policy.mjs` | `c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae` |

Linux 备份：`/var/backups/devspace-tool-policy/server.js.before`。
Windows 备份：`C:\ProgramData\DevSpaceToolPolicy\server.js.before`。

**最后仍需要在 ChatGPT 中点击刷新该 MCP 的工具定义**。服务器端进程重启不自动刷新已有对话中的工具元数据；刷新后即可使用新版说明。
