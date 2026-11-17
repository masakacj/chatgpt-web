#!/usr/bin/env bash
# Download a pinned, reviewed DevSpace Admin MCP kit; validate before sudo.
set -Eeuo pipefail
ACTION="${1:-install}"
case "$ACTION" in install|status|uninstall) ;; *) echo "Use install | status | uninstall" >&2; exit 2;; esac
BASE="https://raw.githubusercontent.com/masakacj/chatgpt-web/release/mcp-admin-broker-20261117/tools/devspace-admin-mcp"
SHA256="6c40e1d445ab7e316ec0cd7ffbbf7487e024e731fee8ef87f7fe7d7ebddbfc86"
TMP="$(mktemp -d /tmp/devspace-admin-download.XXXXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
curl --fail --silent --show-error --location --retry 3 --max-time 40 \
  "$BASE/devspace-admin-mcp-runtime.tar.gz" --output "$TMP/kit.tar.gz"
printf '%s  %s\n' "$SHA256" "$TMP/kit.tar.gz" | sha256sum -c - || exit 3
tar -tzf "$TMP/kit.tar.gz" >/dev/null
tar -xzf "$TMP/kit.tar.gz" -C "$TMP"
[[ -f "$TMP/install.sh" && -f "$TMP/src/handler.mjs" && \
   -f "$TMP/src/adminctl.py" && -f "$TMP/src/jobs/optimizer-v2-import.py" ]] || exit 4
if [[ "$ACTION" == "status" ]]; then
  bash "$TMP/install.sh" status
else
  sudo env DEVSPACE_ADMIN_SOURCE_DIR="$TMP/src" bash "$TMP/install.sh" "$ACTION"
fi
