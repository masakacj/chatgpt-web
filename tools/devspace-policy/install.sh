#!/usr/bin/env bash
# DevSpace tool-use policy installer (Linux). Only downloads SHA-256 pinned code.
set -Eeuo pipefail
ACTION="${1:-apply}"
case "$ACTION" in apply|status|check|rollback) ;; *) echo 'Usage: install.sh apply|status|check|rollback' >&2; exit 2;; esac
BASE='https://raw.githubusercontent.com/masakacj/chatgpt-web/release/devspace-tool-policy-multihost-20261118-r2/tools/devspace-policy'
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
  sudo node "$TMP/policy.mjs" "$ACTION"
else
  node "$TMP/policy.mjs" "$ACTION"
fi
