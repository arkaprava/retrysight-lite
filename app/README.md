# RetrySight Lite Desktop (Flutter)

Native cross-platform GUI for RetrySight Lite — a Flutter desktop app for **macOS**, **Windows**, and **Linux**.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x (stable channel)
- Node.js **22.5+** (for the headless manager backend: collectors, SQLite, REST API)
- Built manager: `cd ../manager && npm install && npm run build`

Platform build tools:

| OS | Requirements |
|----|----------------|
| macOS | Xcode, CocoaPods |
| Windows | Visual Studio 2022 with Desktop development with C++ |
| Linux | `clang`, `cmake`, `ninja-build`, GTK 3 dev packages |

## Run (development)

```bash
cd app
flutter pub get
flutter run -d macos    # or: windows, linux
```

On first launch the app will:

1. Auto-detect `../manager` as the backend path (override with `RETRYSIGHT_MANAGER` or Settings)
2. Read the admin token from OS secure storage (Keychain / DPAPI / libsecret); if none is saved, read it from `manager/data/admin-token` and save it to secure storage
3. Auto-start the headless Node manager (`RETRYSIGHT_HEADLESS=1`) if not already running

You can change host, port, paths, and auto-start in **Settings**.

## Build (release)

```bash
flutter build macos     # → build/macos/Build/Products/Release/RetrySight Lite.app
flutter build windows   # → build/windows/x64/runner/Release/
flutter build linux     # → build/linux/x64/release/bundle/
```

## Screens

| Screen | Description |
|--------|-------------|
| Dashboard | KPIs, cost metrics, charts, filters (range/tool/model/agent) |
| Tasks | Task list + timeline detail |
| Collectors | In-process collectors + registered agents |
| MCP | MCP JSON config (copy to clipboard) |
| Settings | Connection, backend path, admin token, collector paths |

## Architecture

```
Flutter app (Dart UI)
    ↓ HTTP REST (Bearer admin token)
Node manager headless (127.0.0.1:18081)
    ↓
SQLite + in-process collectors (Cursor / Claude Code / Warp-Oz / Windsurf / Cline / Aider / Continue / Copilot)
```

The Flutter app owns the **GUI layer** in Dart. The Node `manager/` process provides the API, database, and log collectors — same as `npm run dev:api` / `RETRYSIGHT_HEADLESS=1`.

## Configuration

Non-secret settings are persisted locally via `shared_preferences`. The admin token is stored in OS secure storage (`flutter_secure_storage`) and is **never** written to plaintext preferences.

Defaults:

| Setting | Default | Storage |
|---------|---------|---------|
| Host | `127.0.0.1` | prefs |
| Port | `18081` | prefs |
| Manager path | `../manager` (relative to repo) | prefs |
| Data dir | `{manager}/data` | prefs |
| Auto-start backend | on | prefs |
| Admin token | from secure storage, else `manager/data/admin-token` | secure storage |
| Collector watch paths | Per-tool defaults when empty | prefs |

Installed backend data dirs (when not using dev `manager/data`):

- macOS: `~/Library/Application Support/RetrySightLite/data`
- Linux: `~/.local/share/RetrySightLite/data` (or `$XDG_DATA_HOME/RetrySightLite/data`)
- Windows: `%LOCALAPPDATA%\RetrySightLite\data`

## Troubleshooting

- **Backend offline:** Ensure Node 22.5+ is on `PATH` and `manager/dist/index.js` exists (`npm run build` in `manager/`).
- **401 Unauthorized:** Set admin token in Settings (copy from `manager/data/admin-token`).
- **No tasks:** Use Cursor/Claude Code locally or run `npm run seed` from the repo root.
- **Tests:** `flutter analyze && flutter test`

## License

Apache-2.0 — see [../LICENSE](../LICENSE).
