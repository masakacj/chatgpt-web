#!/usr/bin/env bash
# R4 DevSpace multi-host policy installer: base v2 + bash.command description repair.
set -Eeuo pipefail
action="${1:-apply}"
case "$action" in apply|check|status|rollback) ;; *) echo 'Usage: install.sh apply|check|status|rollback' >&2; exit 2 ;; esac

base_url='https://raw.githubusercontent.com/masakacj/chatgpt-web/a28850b162344bc7595d6d8d4124fb77003b5597/tools/devspace-policy'
fix_url='https://raw.githubusercontent.com/masakacj/chatgpt-web/6e89a45a9014334ebf96cb8dbb1b519587bae84b/tools/devspace-policy/fix-bash-parameter.mjs'
base_gzip_sha='22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8'
base_src_sha='c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae'
fix_sha='f2ebb1b83358d8e3eadbaaa6267b35420a2735a2b5089236ed376563c39a9960'
tmp="$(mktemp -d /tmp/devspace-policy-r4.XXXXXXXX)"
trap 'rm -rf -- "$tmp"' EXIT

curl -fsSL --max-time 40 "$base_url/devspace-tool-policy.mjs.gz" -o "$tmp/base.mjs.gz"
curl -fsSL --max-time 40 "$fix_url" -o "$tmp/fix.mjs"
printf '%s  %s\n' "$base_gzip_sha" "$tmp/base.mjs.gz" | sha256sum -c -
printf '%s  %s\n' "$fix_sha" "$tmp/fix.mjs" | sha256sum -c -
gzip -dc "$tmp/base.mjs.gz" > "$tmp/base.mjs"
printf '%s  %s\n' "$base_src_sha" "$tmp/base.mjs" | sha256sum -c -
node --check "$tmp/base.mjs"
node --check "$tmp/fix.mjs"

if [ "$action" = check ]; then
  node "$tmp/base.mjs" check
  sudo node "$tmp/fix.mjs" check
elif [ "$action" = status ]; then
  sudo node "$tmp/base.mjs" status
  sudo node "$tmp/fix.mjs" status
elif [ "$action" = rollback ]; then
  sudo node "$tmp/fix.mjs" rollback
  sudo node "$tmp/base.mjs" rollback
else
  preflight="$(node "$tmp/base.mjs" check)"
  printf '%s\n' "$preflight"
  base_installed=false
  if grep -q '"alreadyInstalled": true' <<< "$preflight"; then base_installed=true; fi
  sudo node "$tmp/base.mjs" apply
  sudo node "$tmp/fix.mjs" apply
  if systemctl is-active --quiet devspace.service; then
    if [ "$base_installed" = true ]; then
      sudo systemd-run --quiet --unit="devspace-policy-r4-restart-$$" --on-active=5s /usr/bin/systemctl restart devspace.service
      node_bin="$(command -v node)"
      [ -x "$node_bin" ] || { echo 'Node executable unavailable; refusing watchdog schedule' >&2; exit 1; }
      sudo systemd-run --quiet --unit="devspace-policy-r4-watchdog-$" --on-active=40s "$node_bin" /var/backups/devspace-tool-policy/devspace-tool-policy.mjs watchdog
      echo '{"restart":{"scheduled":true,"method":"systemd-run"},"watchdog":{"scheduled":true}}'
    else
      echo '{"restart":{"scheduled":true,"method":"base-policy-installer"},"watchdog":{"scheduled":true}}'
    fi
  else
    echo '{"restart":{"scheduled":false,"method":"manual","reason":"devspace.service is not active"}}'
  fi
fi
