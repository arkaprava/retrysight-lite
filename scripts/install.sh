#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# RetrySight Lite desktop installer
#   curl -fsSL https://app.retrysight.com/install.sh | bash
#
# Environment:
#   RETRYSIGHT_VERSION     — default: latest (from manifest)
#   RETRYSIGHT_INSTALL_BASE — default: https://app.retrysight.com/lite
#   RETRYSIGHT_INSTALL_DIR — override install location

set -euo pipefail

INSTALL_BASE="${RETRYSIGHT_INSTALL_BASE:-https://app.retrysight.com/lite}"
VERSION="${RETRYSIGHT_VERSION:-latest}"
MANIFEST_URL="${INSTALL_BASE}/${VERSION}/manifest.json"
if [[ "${VERSION}" == "latest" ]]; then
  MANIFEST_URL="${INSTALL_BASE}/latest/manifest.json"
fi

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    darwin) os="darwin" ;;
    linux) os="linux" ;;
    *) die "Unsupported OS: $(uname -s). Use Windows installer: https://app.retrysight.com/install.ps1" ;;
  esac
  arch="$(uname -m)"
  case "$arch" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64) arch="x64" ;;
    *) die "Unsupported CPU architecture: $arch" ;;
  esac
  printf '%s %s\n' "$os" "$arch"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    die "Need shasum or sha256sum to verify downloads"
  fi
}

fetch_manifest() {
  need_cmd curl
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$MANIFEST_URL" -o "$tmp" || die "Could not fetch manifest: $MANIFEST_URL"
  echo "$tmp"
}

pick_download() {
  local manifest="$1" os="$2" arch="$3"
  python3 - "$manifest" "$os" "$arch" <<'PY'
import json, sys
manifest_path, os_name, arch = sys.argv[1:4]
with open(manifest_path) as f:
    data = json.load(f)
for item in data.get("downloads", []):
    if item.get("platform") == os_name and item.get("arch") == arch:
        print(json.dumps(item))
        sys.exit(0)
ids = []
if os_name == "darwin" and arch == "arm64":
    ids = ["macos-arm64"]
elif os_name == "darwin" and arch == "x64":
    ids = ["macos-x64"]
elif os_name == "linux" and arch == "x64":
    ids = ["linux-x64"]
for dl in data.get("downloads", []):
    if dl.get("id") in ids:
        print(json.dumps(dl))
        sys.exit(0)
sys.exit(1)
PY
}

install_macos() {
  local file="$1" kind="$2" app_name="RetrySight Lite.app"
  local apps_dir="${RETRYSIGHT_INSTALL_DIR:-/Applications}"

  if [[ "$kind" == "dmg" ]]; then
    need_cmd hdiutil
    local mount="/Volumes/RetrySight Lite"
    hdiutil attach "$file" -nobrowse -quiet
    rm -rf "${apps_dir}/${app_name}"
    cp -R "${mount}/${app_name}" "${apps_dir}/"
    hdiutil detach "$mount" -quiet
  else
    local tmp
    tmp="$(mktemp -d)"
    tar -xzf "$file" -C "$tmp"
    rm -rf "${apps_dir}/${app_name}"
    cp -R "${tmp}/app-macos-"*"/${app_name}" "${apps_dir}/" 2>/dev/null \
      || cp -R "${tmp}/"*"/${app_name}" "${apps_dir}/"
    rm -rf "$tmp"
  fi
  info "Installed ${apps_dir}/${app_name}"
  info "Open from Launchpad or: open -a 'RetrySight Lite'"
}

install_linux() {
  local file="$1"
  local prefix="${RETRYSIGHT_INSTALL_DIR:-${HOME}/.local/share/retrysight-lite-app}"
  local tmp
  tmp="$(mktemp -d)"
  tar -xzf "$file" -C "$tmp"
  rm -rf "$prefix"
  mkdir -p "$prefix"
  if [[ -d "${tmp}/app-linux-x64/bundle" ]]; then
    cp -R "${tmp}/app-linux-x64/bundle/." "$prefix/"
  else
    cp -R "${tmp}/"*"/bundle/." "$prefix/" 2>/dev/null || cp -R "${tmp}/"*"/." "$prefix/"
  fi
  rm -rf "$tmp"
  local bin="${HOME}/.local/bin"
  mkdir -p "$bin"
  if [[ -x "${prefix}/retrysightlite" ]]; then
    ln -sfn "${prefix}/retrysightlite" "${bin}/retrysight-lite"
  fi
  info "Installed RetrySight Lite → ${prefix}"
  info "Run: ${prefix}/retrysightlite"
}

main() {
  need_cmd python3
  read -r OS ARCH < <(detect_platform)
  info "RetrySight Lite installer (${OS}/${ARCH})"
  info "Fetching manifest from ${MANIFEST_URL}"

  local manifest tmpdir artifact url filename expected_sha kind
  manifest="$(fetch_manifest)"
  artifact="$(pick_download "$manifest" "$OS" "$ARCH")" \
    || die "No release artifact for ${OS}/${ARCH} in manifest"
  url="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["url"])' "$artifact")"
  filename="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["filename"])' "$artifact")"
  expected_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["sha256"])' "$artifact")"
  kind="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("kind","tar.gz"))' "$artifact")"

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  info "Downloading ${filename}"
  curl -fsSL "$url" -o "${tmpdir}/${filename}"

  local actual_sha
  actual_sha="$(sha256_file "${tmpdir}/${filename}")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    die "Checksum mismatch for ${filename}"
  fi
  info "Checksum verified"

  case "$OS" in
    darwin) install_macos "${tmpdir}/${filename}" "$kind" ;;
    linux) install_linux "${tmpdir}/${filename}" ;;
  esac

  info "Done. No Node.js required — backend is bundled in the app."
}

main "$@"
