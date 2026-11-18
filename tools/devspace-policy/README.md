# DevSpace MCP Tool Policy Multi-Host (R2 — Windows 1.0.7/ Linux 1.0.8)

修复第一次部署遇到的“expected exactly one serverInstructions intro; got 2”预检失败，并更新最小化/完整模式的 Bash 说明。旧安装器不需要回滚，因为预检未修改源码。

# DevSpace MCP 工具说明多机一键补丁（2026-11-18）

适用于使用 `@waishnav/devspace` 1.x 的 mcpdebian、mcpoffice、mcpofficeserver 等主机。**只修改 DevSpace 的 MCP 总体使用指令与 bash 工具描述**，让其准确描述经授权的 Git、依赖安装、systemd/Docker/Portainer 部署、配置维护、日志排查等用途。

不增加新的 MCP 连接或端口，不改变认证、权限、实际 Shell 执行器，也不会绕过 ChatGPT 安全检查或解决连接 `link_id` 错误。

## Debian / Linux（一行安装）

```bash
curl -fsSLo /tmp/devspace-policy-install.sh 'https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118-r2/tools/devspace-policy/install.sh' && printf '%s  %s\n' 'daa1b11b69ca0ad35d0fd56a6e992a7c97c05d4978cf222a9dab1f67f6a1952c' '/tmp/devspace-policy-install.sh' | sha256sum -c - && bash /tmp/devspace-policy-install.sh apply
```

### Windows PowerShell（以管理员身份运行）

```powershell
$p=Join-Path $env:TEMP 'devspace-policy-install.ps1'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118-r2/tools/devspace-policy/install.ps1' -OutFile $p; if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne '5c93c3a83be63e4d4ca6e103f5324245387c684ccbeeb2d8b1ea0b892aa32165') { throw 'Installer hash mismatch' }; & $p apply
```

每台机器独立执行一次。Linux 的 systemd `devspace.service` 会被安排重启和健康检查；Windows 端若无名为 `devspace` 的服务，则应用补丁后必须手动重启 DevSpace。切勿在业务高峰期重启正在执行任务的 MCP。

## 状态 / 回滚

Linux：`bash /tmp/devspace-policy-install.sh status`、`bash /tmp/devspace-policy-install.sh rollback`。
Windows：`& $p status`、`& $p rollback`（管理员 PowerShell）。

安装前先严格匹配源码中的四段原始说明（不匹配则拒绝修改），备份到 Linux `/var/backups/devspace-tool-policy` / Windows `%ProgramData%\DevSpaceToolPolicy`。只允许回滚校验值仍匹配的文件，避免覆盖后续升级。重复安装是幂等的；支持回滚后重新安装。

所有下载先验证压缩包 SHA-256，再验证解压文件 SHA-256。完整源代码保存在压缩包内，下载后可查看。

| 文件 | SHA-256 |
| --- | --- |
| `install.sh` | `daa1b11b69ca0ad35d0fd56a6e992a7c97c05d4978cf222a9dab1f67f6a1952c` |
| `install.ps1` | `5c93c3a83be63e4d4ca6e103f5324245387c684ccbeeb2d8b1ea0b892aa32165` |
| `devspace-tool-policy.mjs.gz` | `22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8` |
| 解压源码 `devspace-tool-policy.mjs` | `c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae` |

安装后在 ChatGPT 中重新连接对应 DevSpace MCP，刷新 Bash 工具说明。


## R2 检查

- `serverInstructions` 支持 1/2 个分支，并验证数量。
- Bash 的 `toolNames.shell` 动态文本按原样匹配、正确处理两个模式。
- 增加 Codex 模式及完整模式说明的兼容修改。
- Windows 跳过使用 shell:true 执行 npm.cmd 导致的 DEP0190 警告。
- 本地 5 项测试通过，并已与实际 Windows DevSpace 1.0.7 / Linux DevSpace 1.0.8 源码匹配结果核对。
- 仅修改工具说明和 MCP 指令，不提供新权限，也不能绕过 ChatGPT 安全检查。
