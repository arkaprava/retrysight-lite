#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PREFIX="${RETRYSIGHT_PREFIX:-$HOME/Library/Application Support/RetrySightLite}"
LAUNCH_AGENTS="${HOME}/Library/LaunchAgents"
LABEL="com.retrysightlite.app"
PLIST="${LAUNCH_AGENTS}/${LABEL}.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BIN_SRC=""
if [[ -x "${SCRIPT_DIR}/retrysight-lite" ]]; then
  BIN_SRC="${SCRIPT_DIR}/retrysight-lite"
elif [[ -x "${SCRIPT_DIR}/../release/macos-arm64/retrysight-lite" && "$(uname -m)" == "arm64" ]]; then
  BIN_SRC="${SCRIPT_DIR}/../release/macos-arm64/retrysight-lite"
elif [[ -x "${SCRIPT_DIR}/../release/macos-x64/retrysight-lite" ]]; then
  BIN_SRC="${SCRIPT_DIR}/../release/macos-x64/retrysight-lite"
else
  echo "error: retrysight-lite binary not found next to this script. Run npm run dist:mac first." >&2
  exit 1
fi

mkdir -p "${PREFIX}/bin" "${PREFIX}/data" "${LAUNCH_AGENTS}"
# Data dir contains DB + tokens — restrict to the current user only
chmod 700 "${PREFIX}" "${PREFIX}/data"
cp "${BIN_SRC}" "${PREFIX}/bin/retrysight-lite"
chmod 755 "${PREFIX}/bin/retrysight-lite"

# Optional symlink into ~/bin if present or create ~/.local/bin
LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "${LOCAL_BIN}"
ln -sfn "${PREFIX}/bin/retrysight-lite" "${LOCAL_BIN}/retrysight-lite"

cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PREFIX}/bin/retrysight-lite</string>
    <string>--headless</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>RETRYSIGHT_HEADLESS</key>
    <string>1</string>
    <key>RETRYSIGHT_HOST</key>
    <string>127.0.0.1</string>
    <key>RETRYSIGHT_DATA_DIR</key>
    <string>${PREFIX}/data</string>
    <key>RETRYSIGHT_DB_PATH</key>
    <string>${PREFIX}/data/retrysight-lite.db</string>
    <key>NODE_OPTIONS</key>
    <string>--experimental-sqlite</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${PREFIX}/data/retrysight-lite.log</string>
  <key>StandardErrorPath</key>
  <string>${PREFIX}/data/retrysight-lite.err.log</string>
  <key>WorkingDirectory</key>
  <string>${PREFIX}</string>
</dict>
</plist>
EOF

launchctl unload "${PLIST}" 2>/dev/null || true
launchctl load "${PLIST}"
launchctl start "${LABEL}" 2>/dev/null || true

echo "Installed RetrySightLite → ${PREFIX}"
echo "  binary:  ${PREFIX}/bin/retrysight-lite  (also ${LOCAL_BIN}/retrysight-lite)"
echo "  service: ${PLIST} (LaunchAgent, headless on 127.0.0.1:18081)"
echo "  data:    ${PREFIX}/data"
echo "  TUI:     RETRYSIGHT_DATA_DIR=\"${PREFIX}/data\" retrysight-lite"
echo "  tokens:  ${PREFIX}/data/admin-token  and  ${PREFIX}/data/agent-api-key"
echo "Uninstall: launchctl unload \"${PLIST}\"; rm -rf \"${PREFIX}\" \"${PLIST}\" \"${LOCAL_BIN}/retrysight-lite\""
