#!/usr/bin/env bash
# Fresh Linux x64/arm64 DevSpace deployment. Run as the target non-root user.
set -euo pipefail
umask 077
CORE_URL='https://raw.githubusercontent.com/masakacj/chatgpt-web/57fe0125c214689c399d093a0064d84bcb15bddf/tools/devspace-oneclick/installer.mjs'
CORE_SHA='220b70ed339d09b534d0c8c55c0c261962aee9fb0f82ce5fe58a9ace3fbf30df'
NODE_VERSION='24.22.3'
root="$HOME/.local/share/devspace-oneclick"
workspace=''
profile="${DEVSPACE_PROFILE_FILE:-}"
quick=0
noauto=0
testonly=0
while [ "$#" -gt 0 ]; do
 case "$1" in
  --root) root="$2"; shift 2;;
  --workspace) workspace="$2"; shift 2;;
  --profile) profile="$2"; shift 2;;
  --quick) quick=1; shift;;
  --no-autostart) noauto=1; shift;;
  --test-only) testonly=1; shift;;
  *) echo 'Unknown installer option' >&2; exit 2;;
 esac
done
[ "$(id -u)" -ne 0 ] || { echo 'Run as the target non-root user (not sudo bash).' >&2; exit 1; }
[ "$(uname -s)" = Linux ] || { echo 'Linux only' >&2; exit 1; }
case "$(uname -m)" in
 x86_64|amd64) arch=x64; node_sha='4f2b175a6d53a5c617a80dba2676238a0688cef28c6da4eba35c7d844e66fcfb';;
 aarch64|arm64) arch=arm64; node_sha='6e51a2ada00f0011cc266f65d98922b403d7ad88f809ca2aa615a5fe1ce6e86c';;
 *) echo 'Unsupported CPU architecture' >&2; exit 1;;
esac
case "$root" in /*) ;; *) root="$PWD/$root";; esac
[ "$root" != / ] && [ "$root" != "$HOME" ] || { echo 'Choose a dedicated install directory' >&2; exit 1; }
if [ -n "$profile" ]; then [ -f "$profile" ] || { echo 'Private profile file missing' >&2; exit 1; }; fi
if [ -z "$profile" ] && [ "$quick" = 0 ] && [ "$testonly" = 0 ] && [ ! -f "$root/private/deployment.json" ]; then
 echo 'Named tunnel needs a privately provisioned profile. Use --profile FILE; --quick is temporary.' >&2; exit 1
fi
missing=0
for util in curl tar xz sha256sum git; do
 command -v "$util" >/dev/null 2>&1 || missing=1
done
if [ "$missing" = 1 ]; then
 if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  if command -v apt-get >/dev/null 2>&1; then
   sudo -n apt-get install -y curl tar xz-utils coreutils git ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
   sudo -n dnf install -y curl tar xz coreutils git ca-certificates
  fi
 fi
 for util in curl tar xz sha256sum git; do
  command -v "$util" >/dev/null 2>&1 || { echo "Missing prerequisite $util; a system administrator must install it." >&2; exit 1; }
 done
fi
mkdir -p "$root/downloads" "$root/tools" "$root/tmp" "$root/npm-cache"
free_k=$(df -Pk "$root" | awk 'END {print $4}')
if [ ! -d "$root/program/devspace-1.1.1" ] && [ "$free_k" -lt 4194304 ]; then
 echo 'Installation volume needs at least 4 GiB free. Use --root on another disk.' >&2; exit 1
fi
export TEMP="$root/tmp" TMP="$root/tmp" TMPDIR="$root/tmp" NPM_CONFIG_CACHE="$root/npm-cache"
download(){
 local url="$1" dest="$2" digest="$3" part="$2.part-$$"
 if [ -f "$dest" ] && printf '%s  %s\n' "$digest" "$dest" | sha256sum -c - >/dev/null 2>&1; then return; fi
 curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 300 --output "$part" "$url" || { rm -f "$part"; return 1; }
 printf '%s  %s\n' "$digest" "$part" | sha256sum -c - >/dev/null || { rm -f "$part"; return 1; }
 mv -f "$part" "$dest"
}
compatible(){
 [ -x "$1" ] && "$1" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>=27||a<22||(a===22&&b<19)?1:0)' >/dev/null 2>&1
}
node="$root/tools/node/bin/node"
if ! compatible "$node"; then
 system_node="$(command -v node || true)"
 if [ -n "$system_node" ] && compatible "$system_node" && command -v npm >/dev/null 2>&1; then
  node="$system_node"
 else
  base="node-v$NODE_VERSION-linux-$arch"
  archive="$root/downloads/$base.tar.xz"
  download "https://nodejs.org/dist/v$NODE_VERSION/$base.tar.xz" "$archive" "$node_sha"
  stage="$(mktemp -d "$root/tools/node-stage.XXXXXXXX")"
  tar -xJf "$archive" -C "$stage"
  compatible "$stage/$base/bin/node" || { echo 'Portable Node check failed' >&2; exit 1; }
  if [ -e "$root/tools/node" ]; then mv "$root/tools/node" "$root/tools/node.old-$$"; fi
  mv "$stage/$base" "$root/tools/node"
  rmdir "$stage"
  node="$root/tools/node/bin/node"
 fi
fi
export PATH="$(dirname "$node"):$PATH"
git --version
bash --version | sed -n '1p'
core="$root/installer.mjs"
download "$CORE_URL" "$core" "$CORE_SHA"
args=("$core" deploy --root "$root")
[ -z "$workspace" ] || args+=(--workspace "$workspace")
[ -z "$profile" ] || args+=(--profile "$profile")
[ "$quick" = 0 ] || args+=(--quick)
[ "$noauto" = 0 ] || args+=(--no-autostart)
[ "$testonly" = 0 ] || args+=(--test-only)
exec "$node" "${args[@]}"

