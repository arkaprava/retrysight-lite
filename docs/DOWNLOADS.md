# Hosting RetrySight Lite downloads

End-user install:

```bash
curl -fsSL https://app.retrysight.com/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://app.retrysight.com/install.ps1 | iex
```

## Recommended layout (`app.retrysight.com`)

Serve static files from object storage (Cloudflare R2, S3, or GitHub Pages on a subdomain):

```
app.retrysight.com/
├── install.sh              ← curl | bash entrypoint
├── install.ps1             ← Windows entrypoint
├── lite/
│   ├── latest/
│   │   ├── manifest.json   ← platform → URL + sha256
│   │   ├── retrysight-lite-1.0.0-macos-arm64.dmg
│   │   ├── retrysight-lite-1.0.0-linux-x64.tar.gz
│   │   └── retrysight-lite-1.0.0-win-x64.zip
│   └── v1.0.0/             ← pinned version (same files)
│       ├── manifest.json
│       └── …
```

After `npm run dist:app:all && npm run manifest`, upload **`release/cdn-staging/`** to your bucket as the site root (maps 1:1 to the tree above).

## Build pipeline

| Platform | Build command | Artifact |
| -------- | ------------- | -------- |
| macOS Apple Silicon | `npm run dist:app:mac` | `.dmg` + `.tar.gz` |
| macOS Intel | `npm run dist:app:mac:x64` | `.dmg` + `.tar.gz` |
| Linux x64 | `npm run dist:app:linux` | `.tar.gz` |
| Windows x64 | `npm run dist:app:win` (Windows or CI) | `.zip` |
| All (this Mac) | `npm run dist:app:all` | macOS + Linux |

GitHub Actions (all platforms):

```bash
gh workflow run release-desktop.yml -f target=all
```

Download CI artifacts, copy into `release/`, then:

```bash
npm run manifest
npm run stage:cdn
```

## Hosting options

### Option A — Cloudflare R2 + custom domain (recommended)

1. Create R2 bucket `retrysight-app-downloads`
2. Bind custom domain `app.retrysight.com` (Cloudflare dashboard → R2 → Public access)
3. Upload `release/cdn-staging/*` after each release
4. Set `Content-Type: text/plain; charset=utf-8` for `install.sh`
5. Enable caching; artifacts are immutable per version path

**Pros:** Fast global CDN, cheap egress, full control over `curl | bash` URL  
**Cons:** Manual or scripted upload step

### Option B — GitHub Releases + manifest on R2

1. CI publishes assets to GitHub Releases (`retrysight-lite-v1.0.0`)
2. `manifest.json` URLs point to `https://github.com/arkaprava/retrysight-lite/releases/download/v1.0.0/...`
3. Host only `install.sh` + `install.ps1` + `latest/manifest.json` on `app.retrysight.com`

**Pros:** Free artifact hosting, release notes integration  
**Cons:** GitHub URLs in manifest; rate limits for heavy enterprise rollouts

### Option C — Same origin as marketing site

Add a `/downloads/` route on `retrysight.com` (Astro `public/` or CDN proxy).  
Use `app.retrysight.com` as CNAME to the same bucket for a clean install URL.

## Release checklist

1. Bump `version` in root `package.json`
2. `npm install && npm run install:app`
3. `npm run dist:app:all` (local) + `gh workflow run release-desktop.yml -f target=win-x64`
4. `npm run manifest` — regenerates `release/manifest.json` with SHA-256
5. `npm run stage:cdn` — refreshes `release/cdn-staging/`
6. Upload staging folder to R2 / S3
7. Smoke test:
   ```bash
   RETRYSIGHT_INSTALL_BASE=https://app.retrysight.com/lite curl -fsSL https://app.retrysight.com/install.sh | bash
   ```
8. Flip `unavailableLinks.liteDownload = false` in `retrysight-website/src/data/site.ts`
9. Update `liteDownloads` filenames to match manifest

## Security notes

- Install scripts verify **SHA-256** from `manifest.json` before extracting
- Pin versions in production: `RETRYSIGHT_VERSION=v1.0.0 curl … | bash`
- Serve install scripts over HTTPS only
- Consider code-signing macOS (Developer ID) and Windows (Authenticode) for Gatekeeper/SmartScreen

## Environment variables (install scripts)

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `RETRYSIGHT_INSTALL_BASE` | `https://app.retrysight.com/lite` | Manifest + artifact base |
| `RETRYSIGHT_VERSION` | `latest` | `latest` or `v1.0.0` |
| `RETRYSIGHT_INSTALL_DIR` | OS default | Override install path |
