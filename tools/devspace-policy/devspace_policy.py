#!/usr/bin/env python3
"""DevSpace 1.0.7/1.0.8 tool-policy update, Linux/Windows.

Only changes the human-readable serverInstructions and bash tool descriptions.
No changes to exec implementation, OAuth, sudo, annotations, or platform checks.
Usage: python devspace_policy.py status|test|apply|rollback
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

MARKER = "DevSpace authorized deployment guidance 2026-11-18"
VERSIONS = {"1.0.7", "1.0.8"}
WIN = os.name == "nt"
STATE = (Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "DevSpacePolicy-20261118"
         if WIN else Path("/var/backups/devspace-policy-20261118"))
BACKUP = STATE / "server.js.before"
MANIFEST = STATE / "manifest.json"
SHELL = "$" + "{toolNames.shell}"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def stop(message):
    raise SystemExit("ERROR: " + message)

def locate():
    paths = []
    explicit = os.environ.get("DEVSPACE_SERVER_PATH")
    if explicit:
        paths.append(Path(explicit))
    else:
        cmd = shutil.which("devspace")
        if cmd:
            p = Path(cmd).resolve()
            paths.append(p.parent / "server.js" if p.name == "cli.js"
                         else p.parent / "node_modules/@waishnav/devspace/dist/server.js")
        npm = shutil.which("npm.cmd" if WIN else "npm")
        if npm:
            try:
                run = subprocess.run([npm, "root", "-g"], capture_output=True, text=True, timeout=12)
                if run.returncode == 0:
                    paths.append(Path(run.stdout.strip()) / "@waishnav/devspace/dist/server.js")
            except (OSError, subprocess.TimeoutExpired):
                pass
        paths.extend([Path("/usr/lib/node_modules/@waishnav/devspace/dist/server.js"),
                      Path("/usr/local/lib/node_modules/@waishnav/devspace/dist/server.js")])
        if WIN and os.environ.get("APPDATA"):
            paths.append(Path(os.environ["APPDATA"]) / "npm/node_modules/@waishnav/devspace/dist/server.js")
    paths = sorted({str(p.resolve()) for p in paths if p.is_file()})
    if len(paths) != 1:
        stop("Expected one DevSpace installation; found " + str(paths) +
             ". Set DEVSPACE_SERVER_PATH to select one installation.")
    dest = Path(paths[0])
    pkg = dest.parent.parent / "package.json"
    if not pkg.is_file():
        stop("DevSpace package.json not found")
    info = json.loads(pkg.read_text(encoding="utf-8"))
    if info.get("name") != "@waishnav/devspace" or str(info.get("version")) not in VERSIONS:
        stop("Unsupported DevSpace package/version: " + str(info.get("version")))
    return dest, str(info["version"])

def transform(source):
    if MARKER in source:
        stop("Policy already applied; use status")
    if "DevSpace authorized deployment policy v1" in source:
        stop("Older patch detected; roll it back first")
    pairs = [
        ("Use DevSpace for coding work.",
         "Use DevSpace for coding and explicitly user-authorized builds, deployments, "
         "and system maintenance. " + MARKER + ".", 2),
        ("Do not create or modify files with " + SHELL +
         "; avoid shell redirection, heredocs, tee, sed -i, perl -i, node/python/ruby scripts, "
         "or any command whose purpose is to write project files.",
         "Prefer read/edit/write for normal code changes; shell-based file modifications "
         "are appropriate for authorized deployments and privileged configuration work. "
         "Back up affected state, verify changes, and confirm destructive actions.", 1),
        ("Use only for tests, builds, git inspection, package scripts, search, file discovery, and directory inspection.",
         "Use for tests, builds, Git, dependencies, authorized service/container deployments, "
         "system configuration, maintenance, and diagnostics.", 1),
        ("Use only for tests, builds, git inspection, package scripts, and commands that are better executed by the shell.",
         "Use for tests, builds, Git, dependencies, authorized service/container deployments, "
         "system configuration, maintenance, and diagnostics.", 1),
        ("Do not use " + SHELL + " to create or modify files. Do not use shell redirection, "
         "heredocs, tee, sed -i, perl -i, node/python/ruby scripts, or generated scripts "
         "to write project files;",
         "Prefer read/edit/write for ordinary source edits; shell-based file operations "
         "are appropriate for authorized deployment and system-owned configurations;", 2),
        ("for tests, builds, git inspection, package scripts, and commands that are better executed by the shell.",
         "for tests, builds, Git, packages, authorized deployment, and system maintenance "
         "operations best executed by the shell.", 1),
    ]
    out = source
    for old, new, count in pairs:
        found = out.count(old)
        if found != count:
            stop("Unexpected DevSpace source: expected " + str(count) +
                 " occurrences but found " + str(found) + " for: " + old[:55])
        out = out.replace(old, new)
    if out.count(MARKER) != 2 or out.count("DEVSPACE_OPERATOR_HOOK_V1") != source.count("DEVSPACE_OPERATOR_HOOK_V1"):
        stop("Policy or existing Operator extension validation failed")
    return out.encode("utf-8")

def check_js(data):
    node = shutil.which("node")
    if not node:
        stop("node executable missing")
    fd, name = tempfile.mkstemp(prefix="devspace-policy-check-", suffix=".mjs")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        result = subprocess.run([node, "--check", name], capture_output=True, text=True, timeout=25)
        if result.returncode:
            stop("JavaScript syntax validation failed: " + result.stderr[-240:])
    finally:
        if os.path.exists(name):
            os.unlink(name)

def swap(path, data):
    original = path.stat()
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".policy-", suffix=".mjs")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if not WIN:
            os.chmod(name, stat.S_IMODE(original.st_mode))
            os.chown(name, original.st_uid, original.st_gid)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def admin():
    if WIN:
        try:
            return bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            return False
    return os.geteuid() == 0

def restart():
    if WIN:
        location = os.environ.get("LOCALAPPDATA", "")
        manager = Path(location) / "DevSpaceManaged/devspace-managed.ps1"
        if not manager.is_file():
            return "manual restart required (DevSpaceManaged runner not detected)"
        ps = shutil.which("powershell.exe")
        if not ps:
            return "manual restart required (PowerShell missing)"
        escaped = str(manager).replace("'", "''")
        subprocess.Popen([ps, "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
                          "-ExecutionPolicy", "Bypass", "-Command",
                          "Start-Sleep -Seconds 7; & '" + escaped + "' -Action Restart"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, close_fds=True,
                         creationflags=getattr(subprocess, "DETACHED_PROCESS", 0) |
                         getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
        return "DevSpaceManaged restart scheduled in 7 seconds"
    runner = shutil.which("systemd-run")
    ctl = shutil.which("systemctl")
    if not runner or not ctl:
        return "manual restart required: systemctl restart devspace.service"
    p = subprocess.run([runner, "--quiet", "--unit", "devspace-policy-restart-" + str(os.getpid()),
                        "--on-active=7s", ctl, "restart", "devspace.service"],
                       capture_output=True, text=True, timeout=20)
    if p.returncode:
        stop("Could not schedule DevSpace restart: " + p.stderr[-200:])
    return "systemd restart scheduled in 7 seconds"

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action not in {"status", "test", "apply", "rollback"}:
        stop("Usage: status | test | apply | rollback")
    dest, version = locate()
    current = dest.read_bytes()
    if action == "status":
        print(json.dumps({"ok": True, "host": "Windows" if WIN else "Linux",
                          "version": version, "path": str(dest),
                          "installed": MARKER.encode() in current,
                          "sourceSha256": sha(current),
                          "operatorPresent": b"DEVSPACE_OPERATOR_HOOK_V1" in current,
                          "backupPresent": BACKUP.is_file() if admin() else "requires admin"}, ensure_ascii=False))
        return
    if action == "rollback":
        if not admin():
            stop("Administrator/Root required")
        if not BACKUP.is_file() or not MANIFEST.is_file():
            stop("Backup/manifest not found")
        meta = json.loads(MANIFEST.read_text(encoding="utf-8"))
        old = BACKUP.read_bytes()
        if meta["path"] != str(dest) or sha(old) != meta["before"] or sha(current) != meta["after"]:
            stop("Source changed or backup mismatch; refusing overwrite")
        check_js(old)
        swap(dest, old)
        print(json.dumps({"ok": True, "rolledBack": True, "restart": restart()}))
        return
    if MARKER.encode() in current:
        print(json.dumps({"ok": True, "alreadyApplied": True, "version": version}))
        return
    updated = transform(current.decode("utf-8"))
    check_js(updated)
    if action == "test":
        print(json.dumps({"ok": True, "dryRun": True, "version": version,
                          "jsSyntax": "passed", "oauthChanged": False,
                          "executorChanged": False, "existingOperatorPreserved": True}))
        return
    if not admin():
        stop("Run in an elevated PowerShell or with sudo")
    if BACKUP.exists():
        stop("Prior backup exists with no installed marker; inspect before retrying")
    STATE.mkdir(parents=True, exist_ok=True)
    if not WIN:
        os.chmod(STATE, 0o700)
    BACKUP.write_bytes(current)
    if not WIN:
        os.chmod(BACKUP, 0o600)
    MANIFEST.write_text(json.dumps({"path": str(dest), "version": version,
                                    "before": sha(current), "after": sha(updated)}, indent=2),
                        encoding="utf-8")
    swap(dest, updated)
    try:
        reboot = restart()
    except Exception:
        swap(dest, current)
        raise
    print(json.dumps({"ok": True, "installed": True, "version": version,
                      "host": "Windows" if WIN else "Linux", "restart": reboot,
                      "backup": str(BACKUP), "oldSource": sha(current),
                      "newSource": sha(updated), "oauthChanged": False,
                      "executorChanged": False, "platformRestrictionsChanged": False,
                      "reconnectChatGPT": True}, ensure_ascii=False))

if __name__ == "__main__":
    main()
