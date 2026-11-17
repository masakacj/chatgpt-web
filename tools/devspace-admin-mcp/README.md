# DevSpace Admin MCP (mcpdebian)
A one-click authenticated DevSpace MCP administrative tool extension for the user's Debian host, built as a reversible patch to the installed DevSpace **1.0.8** server. **No new public HTTP port** or generic shell tool is added.

## Online installation
Download and run the immutable-commit `bootstrap.sh` (copy the pinned commit URL from the handoff). It downloads `devspace-admin-mcp-runtime.tar.gz`, validates SHA-256, and asks for local sudo to install. The root-owned installer validates three included source files against their SHA-256, checks upstream DevSpace version and exact source anchors, creates a backup, installs an allowlisted broker and deploy recipes, adds a narrow sudoers line, registers MCP tools, and restarts DevSpace once.

After installation **reconnect the existing mcpdebian app** in ChatGPT to refresh tools.

## MCP tools
- `admin_list`: list approved services and deployment recipes (read-only).
- `admin_service`: manage registered systemd units only; stop/disable require explicit `STOP:<service>` / `DISABLE:<service>`.
- `admin_logs`: bounded systemd logs with basic sensitive-field redaction.
- `admin_deploy`: execute a named root-owned Python deployment recipe pinned by SHA-256; does not accept arbitrary scripts, commands, paths or URLs. Requires `confirmation: "EXECUTE_APPROVED_DEPLOYMENT"`.

The initial registered deployment is **`optimizer-v2-import`**, which imports staged OfficeServer credentials by calling the already-installed private config service's app-scoped admin command. Installation does NOT run this deployment or change existing app configurations.

New systemd services and deployments require a local administrator to approve a new entry in `/etc/devspace-admin-mcp/profiles.json`, and for deployments a root-owned checked script in `/opt/devspace-admin-mcp/jobs` with the exact SHA-256 entered in the registry. Unregistered scripts cannot be executed.

## Safe operations / rollback
`bootstrap.sh status` is read-only. `bootstrap.sh uninstall` restores the saved DevSpace server and restarts it; private config is unchanged.

The Debian `devspace` user already had broad passwordless sudo privileges before this extension. The installer does not grant generic sudo; it exposes **only selected MCP tools**. It cannot disable or override ChatGPT platform policy, permission prompts, or automated safety checks. The tools may still require the user's approval. Do not install on an untrusted MCP server. Re-review source before DevSpace npm upgrades, which may replace the patched server.

The full readable source and offline policy tests are inside the matching ChatGPT artifact bundle. The online distribution uses an immutable bootstrap and a SHA-256-checked source archive.
