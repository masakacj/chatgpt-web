#!/usr/bin/env bash
# SHA-256 pinned DevSpace tool-use policy installer (Linux / systemd).
# New installs get a detached restart and rollback watchdog from the verified policy script.
set -Eeuo pipefail
ACTION=apply
if [ "$#" -gt 0 ]; then ACTION="$1"; fi
case "$ACTION" in apply|status|check|rollback) ;; *) echo 'Usage: install.sh apply|status|check|rollback' >&2; exit 2;; esac
BASE='https://raw.githubusercontent.com/masakacj/chatgpt-web/a28850b162344bc7595d6d8d4124fb77003b5597/tools/devspace-policy'
ARCHIVE_SHA256='22a131c17958493141bdafccffe643b066c1e36e72789e46c6999b11d1a7f9d8'
SOURCE_SHA256='c99722874505ef0598fa30af8d41a8880297a08c3bda0b447a2a3d967a9421ae'
TMP="$(mktemp -d /tmp/devspace-tool-policy.XXXXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
curl --fail --silent --show-error --location --retry 3 --max-time 40 "$BASE/devspace-tool-policy.mjs.gz" --output "$TMP/policy.mjs.gz"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$TMP/policy.mjs.gz" | sha256sum -c -
gzip -dc "$TMP/policy.mjs.gz" > "$TMP/policy.mjs"
printf '%s  %s\n' "$SOURCE_SHA256" "$TMP/policy.mjs" | sha256sum -c -
node "$TMP/policy.mjs" check
if [ "$ACTION" = apply ] || [ "$ACTION" = rollback ]; then
  result="$(sudo node "$TMP/policy.mjs" "$ACTION")"
  printf '%s\n' "$result"
  # A repeated apply may find the patched source but an old, unrefreshed server process.
  # Refresh it detached, only when the existing systemd unit is running.
  if [ "$ACTION" = apply ] && [[ "$result" == *'"alreadyInstalled":true'* ]] &&
     systemctl is-active --quiet devspace.service; then
    unit="devspace-policy-refresh-$(date +%s)-$$"
    sudo systemd-run --quiet --unit="$unit" --on-active=5s /usr/bin/systemctl restart devspace.service
    printf '{"restart":{"scheduled":true,"method":"systemd-run","reason":"reapply_refresh"}}\n'
  fi
else
  node "$TMP/policy.mjs" "$ACTION"
fi
