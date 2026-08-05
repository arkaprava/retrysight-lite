# RetrySight Lite

[License: Apache-2.0](LICENSE)

Local-first console for coding-agent retries, tokens, cost estimates, and agentic metrics.

**Recommended UI:** native Flutter desktop app in `[app/](app/)` (macOS, Windows, Linux).

One Node.js backend process:

- In-process collectors (Cursor, Claude Code, Warp/Oz, Windsurf, Cline, Aider, Continue, GitHub Copilot → SQLite)
- Loopback REST / GraphQL / MCP for tooling
- Terminal TUI (blessed) — legacy; use the Flutter app instead

No separate agent service. No Docker required.

## Quick start

### Flutter desktop (recommended)

```bash
git clone https://github.com/arkaprava/retrysight-lite.git
cd retrysight-lite

cd manager && npm install && npm run build
cd ../app && flutter pub get && flutter run -d macos   # or windows / linux
```

On first launch the app auto-detects `../manager`, reads the admin token from secure storage (or `manager/data/admin-token`), and starts the headless backend if needed.

See `[app/README.md](app/README.md)` for build and configuration details.

### Dev from source (API only)

```bash
npm install
npm run install:app
npm run dev:api          # headless API + collectors (used by Flutter app)
```

API defaults to **127.0.0.1:18081**. Data and secrets live under `manager/data/` in development.

### Dev from source (terminal TUI — legacy)

```bash
cd manager && npm install
npm run dev              # TUI + API + collectors
```


| Key     | Action                  |
| ------- | ----------------------- |
| `1`–`3` | Dashboard / Tasks / MCP |
| `f`     | Cycle filter field      |
| `[` `]` | Change filter value     |
| `Enter` | Task timeline           |
| `r`     | Refresh                 |
| `q`     | Quit                    |




## Install (platform binaries)

Build artifacts land in `release/`.

```bash
npm install
npm run install:app
npm run dist:mac:arm64   # or: dist:mac / dist:linux / dist:win / dist:all
```


| Platform            | Artifact                           | Install                                  |
| ------------------- | ---------------------------------- | ---------------------------------------- |
| macOS Apple Silicon | `release/macos-arm64/` + `.tar.gz` | `./install-macos.sh` (LaunchAgent)       |
| macOS Intel         | `release/macos-x64/` + `.tar.gz`   | `./install-macos.sh`                     |
| Linux x64           | `release/linux-x64/` + `.tar.gz`   | `./install-linux.sh` (systemd user unit) |
| Windows x64         | `release/win-x64/` + `.zip`        | `.\install-windows.ps1` (Scheduled Task) |


Defaults after install:

- API on **127.0.0.1:18081**
- Data + secrets under the install prefix (`~/Library/Application Support/RetrySightLite` on macOS, `~/.local/share/RetrySightLite` on Linux, `%LOCALAPPDATA%\RetrySightLite` on Windows)
- `admin-token` and `agent-api-key` auto-generated on first run



## Security defaults


| Setting                     | Default                                                                                                      |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Bind host                   | `127.0.0.1` (set `RETRYSIGHT_HOST=0.0.0.0` for LAN — intentional only)                                       |
| Host-header guard           | When bound to loopback, non-`127.0.0.1`/`localhost` `Host` headers are rejected (403) — blocks DNS rebinding |
| Admin APIs                  | `Authorization: Bearer $RETRYSIGHT_ADMIN_TOKEN` or `X-RetrySight-Admin-Token`                                |
| Public                      | `GET /api/v1/health` only; all other REST and GraphQL endpoints (incl. `collectors`) require admin           |
| Ingest (optional remote)    | `X-Agent-Api-Key` (scrypt-hashed; verified via `key_prefix` lookup)                                          |
| CORS                        | Disabled (loopback browser origins only for web dev)                                                         |
| GraphQL introspection       | Off (`RETRYSIGHT_GRAPHQL_DEV=1` to enable)                                                                   |
| Secrets                     | Auto-generated into data dir if unset / weak (min length enforced)                                           |
| Data-at-rest permissions    | Data dirs `0700`, SQLite DB/WAL and collector buffer files `0600` (owner-only)                               |
| Token storage (Flutter app) | Admin token in OS secure storage (Keychain / DPAPI / libsecret), never plaintext prefs                       |
| TLS                         | Optional — `RETRYSIGHT_TLS_CERT` + `RETRYSIGHT_TLS_KEY`                                                      |
| Rate limiting               | On by default (20 req/min GraphQL, 60/min ingest, 100/min admin)                                             |
| Data retention              | `RETRYSIGHT_RETENTION_DAYS` (0 = never delete)                                                               |
| API key expiry              | `expires_at` column supported (set programmatically)                                                         |


```bash
# Dashboard (admin)
curl -H "Authorization: Bearer $(cat manager/data/admin-token)" \
  http://127.0.0.1:18081/api/v1/dashboard

# Optional HTTP ingest (remote collectors)
curl -H "X-Agent-Api-Key: $(cat manager/data/agent-api-key)" \
  -H 'content-type: application/json' \
  -d '{"name":"x","developerEmail":"x@local","hostname":"h"}' \
  http://127.0.0.1:18081/api/v1/ingest/heartbeat
```

Report security issues privately — see `[SECURITY.md](SECURITY.md)`.

## MCP

Set `RETRYSIGHT_URL` and `RETRYSIGHT_TOKEN` (same value as admin token):

```json
{
  "mcpServers": {
    "retrysight-lite": {
      "command": "npm",
      "args": ["run", "mcp", "--prefix", "/ABS/PATH/retrysight-lite/manager"],
      "env": {
        "RETRYSIGHT_URL": "http://127.0.0.1:18081",
        "RETRYSIGHT_TOKEN": "<contents of data/admin-token>"
      }
    }
  }
}
```

The Flutter app **MCP** screen generates this JSON from your live config.

## Environment


| Variable                                                                                                                                                                       | Default                  | Notes                                                      |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------ | ---------------------------------------------------------- |
| `RETRYSIGHT_HOST`                                                                                                                                                              | `127.0.0.1`              | Loopback; use `0.0.0.0` for LAN                            |
| `RETRYSIGHT_PORT`                                                                                                                                                              | `18081`                  |                                                            |
| `RETRYSIGHT_PUBLIC_URL`                                                                                                                                                        | `http://127.0.0.1:18081` | External URL for CORS                                      |
| `RETRYSIGHT_ADMIN_TOKEN`                                                                                                                                                       | auto                     | Protects GraphQL + non-ingest REST                         |
| `AGENT_API_KEY`                                                                                                                                                                | auto                     | Optional HTTP ingest                                       |
| `RETRYSIGHT_COLLECTORS`                                                                                                                                                        | on                       | In-process IDE log collectors                              |
| `RETRYSIGHT_CURSOR` / `RETRYSIGHT_CLAUDE` / `RETRYSIGHT_WARP` / `RETRYSIGHT_WINDSURF` / `RETRYSIGHT_CLINE` / `RETRYSIGHT_AIDER` / `RETRYSIGHT_CONTINUE` / `RETRYSIGHT_COPILOT` | on                       | Per-tool collector toggles                                 |
| `RETRYSIGHT_*_PATHS`                                                                                                                                                           | tool defaults            | Override collector watch paths (colon/semicolon-separated) |
| `RETRYSIGHT_POLL_MS`                                                                                                                                                           | `5000`                   | Collector poll interval                                    |
| `RETRYSIGHT_FLUSH_MS`                                                                                                                                                          | `10000`                  | Collector flush interval                                   |
| `RETRYSIGHT_HEADLESS`                                                                                                                                                          | unset                    | `1` = API only (no TUI)                                    |
| `RETRYSIGHT_DATA_DIR`                                                                                                                                                          | `manager/data`           | DB + secrets                                               |
| `RETRYSIGHT_COLLECTOR_DIR`                                                                                                                                                     | `~/.retrysight-lite`     | Offsets / local agent id                                   |
| `RETRYSIGHT_TLS_CERT`                                                                                                                                                          | unset                    | Path to TLS cert (enables HTTPS)                           |
| `RETRYSIGHT_TLS_KEY`                                                                                                                                                           | unset                    | Path to TLS key                                            |
| `RETRYSIGHT_RETENTION_DAYS`                                                                                                                                                    | `0`                      | Auto-delete data older than N days                         |
| `RETRYSIGHT_RETENTION_INTERVAL_MS`                                                                                                                                             | `86400000`               | How often to check for old data                            |


> **Note:** The SQLite database (`retrysight-lite.db`) is not encrypted at rest. To protect data at rest, use full-disk encryption (FileVault on macOS, LUKS on Linux, BitLocker on Windows) or place the data dir on an encrypted volume. The DB/WAL and collector buffer files are chmod'd owner-only (0600) and their directories 0700 on creation.



### Legacy environment names

If you upgraded from an earlier private build, `RETRYSITELITE_*` environment variables and `X-RetrySiteLite-Admin-Token` are still accepted by the backend for compatibility. Prefer the `RETRYSIGHT_*` names for new installs.

### Secret-scan guard

To prevent committing live tokens, run the scanner and install the pre-commit hook:

```bash
./scripts/scan-secrets.sh --all
./scripts/install-git-hooks.sh
```



## Development

```bash
# Backend unit/smoke tests
cd manager && npm run build && npm run smoke

# Flutter tests
cd app && flutter analyze && flutter test
```

See `[CONTRIBUTING.md](CONTRIBUTING.md)` for contribution guidelines.

## Packaging scripts

```bash
npm run dist           # current platform binary + archive → release/
npm run dist:mac       # macos-arm64 + macos-x64
npm run dist:linux     # linux-x64
npm run dist:win       # win-x64
npm run dist:all       # all of the above
```

Uses `esbuild` + `[@yao-pkg/pkg](https://github.com/yao-pkg/pkg)` (Node 22). A `release/portable-*` folder is also produced for running with a system Node 22.5+ install.

## Project layout

```
retrysight-lite/
├── app/              # Flutter native desktop GUI (recommended)
├── manager/          # Backend: collectors, API, GraphQL, MCP, legacy TUI
├── scripts/          # dist + OS installers + seed
├── release/          # build output (gitignored)
└── package.json      # root dist / install scripts
```



## License

Licensed under the [Apache License, Version 2.0](LICENSE). Third-party notices are in `[NOTICE](NOTICE)`.