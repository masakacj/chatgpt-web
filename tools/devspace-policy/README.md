# DevSpace MCP tool-guidance patch · 2026-11-18

This is a **tool description / usage instruction** adjustment for the installed `@waishnav/devspace` package. It is not a new MCP server or plugin.

## Compatibility

- DevSpace **1.0.7**: Windows (verified against the user's `mcpoffice` source)
- DevSpace **1.0.8**: Linux (verified against the user's `mcpofficeserver` source)
- `mcpdebian` was previously verified as 1.0.8, but its current account link could not be queried this turn.
- Supports global npm installs in `/usr/lib/node_modules`, `/usr/local/lib/node_modules`, and Windows user npm global directories.
- Existing DevSpace Operator hooks are preserved.

## Exact fixed version and checksum

Raw file (immutable commit):

`https://raw.githubusercontent.com/masakacj/chatgpt-web/56cfcf15fe394715e8045d006507517a0c4e96d5/tools/devspace-policy/devspace_policy.py`

SHA-256:

`8d23122f2ef07a404e351e22b0cafdf2e0ebb65f978a52e7b49f0ecfad49e733`

## Linux (sudo)

```bash
f=$(mktemp) && curl -fsSL 'https://raw.githubusercontent.com/masakacj/chatgpt-web/56cfcf15fe394715e8045d006507517a0c4e96d5/tools/devspace-policy/devspace_policy.py' -o "$f" && echo "8d23122f2ef07a404e351e22b0cafdf2e0ebb65f978a52e7b49f0ecfad49e733  $f" | sha256sum -c - && python3 "$f" test && sudo python3 "$f" apply
```

Expected: JSON `"installed": true`, and a systemd restart scheduled shortly after the command. Run the command in a local SSH session; an MCP connection may disconnect during restart.

## Windows (run in Administrator PowerShell)

```powershell
$u='https://raw.githubusercontent.com/masakacj/chatgpt-web/56cfcf15fe394715e8045d006507517a0c4e96d5/tools/devspace-policy/devspace_policy.py'; $p=Join-Path $env:TEMP 'devspace_policy_20261118.py'; Invoke-WebRequest -UseBasicParsing $u -OutFile $p; if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLower() -ne '8d23122f2ef07a404e351e22b0cafdf2e0ebb65f978a52e7b49f0ecfad49e733') { throw 'SHA-256 mismatch' }; python $p test; if ($LASTEXITCODE -ne 0) { throw 'DevSpace preflight failed' }; python $p apply; if ($LASTEXITCODE -ne 0) { throw 'DevSpace installation failed' }
```

Expected: JSON `"installed": true`. If the previously installed `DevSpaceManaged` runner exists, it will schedule `-Action Restart`. Otherwise the script reports that a manual restart is needed. It will not terminate an unidentified DevSpace process.

## Status / rollback

Linux:

```bash
python3 /path/to/devspace_policy.py status
sudo python3 /path/to/devspace_policy.py rollback
```

Windows:

```powershell
python $p status
python $p rollback
```

On Linux, rollback backup lives under `/var/backups/devspace-policy-20261118/`. On Windows it lives under `%LOCALAPPDATA%\DevSpacePolicy-20261118`.

The patch verifies anchor counts and performs `node --check` before replacing any DevSpace source. Unknown versions/source layouts fail without changing files. Rollback restores only a matching pre-patch backup: it refuses to overwrite later DevSpace package upgrades.

## What changes and what does not

Changes only (a) `serverInstructions` and (b) the tool description strings for the existing `bash` tool, to explicitly recognize authorized development, deployment, package management, and system maintenance. No existing Bash execution logic, platform checks, OAuth, sudoers, port or tool endpoint changes are made.

**Important:** User or platform security approvals can still block operations. This script cannot fix a ChatGPT `link_id` connection error. Reconnect each MCP after the DevSpace restart to refresh its tool descriptions. When DevSpace is updated, inspect and reapply the policy only after a new version is reviewed.
