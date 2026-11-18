#!/usr/bin/env bash
# DevSpace tool-use policy installer (Linux). Only downloads SHA-256 pinned code.
set -Eeuo pipefail
ACTION="${1:-apply}"
case "$ACTION" in apply|status|check|rollback) ;; *) echo 'Usage: install.sh apply|status|check|rollback' >&2; exit 2;; esac
BASE='https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118/tools/devspace-policy'
ARCHIVE_SHA256='9d5fd70b70cf12b4f3744b9368dea0bce02b4d618512f794a62725b724869b44'
SOURCE_SHA256='77ed48dab778ccb66fdddc20b3b70fa173dd234447fd30c423b5828f454a3850'
TMP="$(mktemp -d /tmp/devspace-tool-policy.XXXXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
curl --fail --silent --show-error --location --retry 3 --max-time 40 "$BASE/devspace-tool-policy.mjs.gz" --output "$TMP/policy.mjs.gz"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$TMP/policy.mjs.gz" | sha256sum -c -
gzip -dc "$TMP/policy.mjs.gz" > "$TMP/policy.mjs"
printf '%s  %s\n' "$SOURCE_SHA256" "$TMP/policy.mjs" | sha256sum -c -
node "$TMP/policy.mjs" check
if [ "$ACTION" = apply ] || [ "$ACTION" = rollback ]; then
  sudo node "$TMP/policy.mjs" "$ACTION"
else
  node "$TMP/policy.mjs" "$ACTION"
fi
