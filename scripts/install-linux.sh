#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PREFIX="${RETRYSIGHT_PREFIX:-$HOME/.local/share/retrysight-lite}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="${UNIT_DIR}/retrysight-lite.service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BIN_SRC=""
if [[ -x "${SCRIPT_DIR}/retrysight-lite" ]]; then
  BIN_SRC="${SCRIPT_DIR}/retrysight-lite"
elif [[ -x "${SCRIPT_DIR}/../release/linux-x64/retrysight-lite" ]]; then
  BIN_SRC="${SCRIPT_DIR}/../release/linux-x64/retrysight-lite"
else
  echo "error: retrysight-lite binary not found. Run npm run dist:linux first." >&2
  exit 1
fi

mkdir -p "${PREFIX}/bin" "${PREFIX}/data" "${UNIT_DIR}" "$HOME/.local/bin"
# Data dir contains DB + tokens — restrict to the current user only
chmod 700 "${PREFIX}" "${PREFIX}/data"
cp "${BIN_SRC}" "${PREFIX}/bin/retrysight-lite"
chmod 755 "${PREFIX}/bin/retrysight-lite"
ln -sfn "${PREFIX}/bin/retrysight-lite" "$HOME/.local/bin/retrysight-lite"

cat > "${UNIT}" <<EOF
[Unit]
Description=RetrySightLite standalone agentic metrics
After=network.target

[Service]
Type=simple
ExecStart=${PREFIX}/bin/retrysight-lite --headless
Restart=on-failure
Environment=RETRYSIGHT_HEADLESS=1
Environment=RETRYSIGHT_HOST=127.0.0.1
Environment=RETRYSIGHT_DATA_DIR=${PREFIX}/data
Environment=RETRYSIGHT_DB_PATH=${PREFIX}/data/retrysight-lite.db
Environment=NODE_OPTIONS=--experimental-sqlite
WorkingDirectory=${PREFIX}

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now retrysight-lite.service

echo "Installed RetrySightLite → ${PREFIX}"
echo "  binary:  ${PREFIX}/bin/retrysight-lite"
echo "  service: systemctl --user status retrysight-lite"
echo "  data:    ${PREFIX}/data"
echo "  tokens:  ${PREFIX}/data/admin-token  and  ${PREFIX}/data/agent-api-key"
echo "Uninstall: systemctl --user disable --now retrysight-lite; rm -rf \"${PREFIX}\" \"${UNIT}\""
