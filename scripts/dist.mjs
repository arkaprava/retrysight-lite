#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

/**
 * Build platform installers / binaries into ./release/
 *
 * Targets (via RETRYSIGHT_DIST_TARGETS or CLI args):
 *   macos-arm64, macos-x64, linux-x64, win-x64, all, current
 */
import { execFileSync } from 'node:child_process'
import {
  copyFileSync,
  cpSync,
  mkdirSync,
  rmSync,
  writeFileSync,
  chmodSync,
} from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import { arch, platform } from 'node:os'
import { run } from './run.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const managerDir = join(root, 'manager')
const releaseDir = join(root, 'release')
const outDir = join(root, 'dist-pkg')
const require = createRequire(import.meta.url)
const managerRequire = createRequire(join(managerDir, 'package.json'))

function managerTscBin() {
  try {
    return managerRequire.resolve('typescript/bin/tsc')
  } catch {
    throw new Error('manager dependencies missing — run npm run install:app')
  }
}

const ALL_TARGETS = {
  'macos-arm64': { pkg: 'node22-macos-arm64', bin: 'retrysight-lite', archive: 'tar' },
  'macos-x64': { pkg: 'node22-macos-x64', bin: 'retrysight-lite', archive: 'tar' },
  'linux-x64': { pkg: 'node22-linux-x64', bin: 'retrysight-lite', archive: 'tar' },
  'win-x64': { pkg: 'node22-win-x64', bin: 'retrysight-lite.exe', archive: 'zip' },
}

function currentTargetKey() {
  const p = platform()
  const a = arch()
  if (p === 'darwin' && a === 'arm64') return 'macos-arm64'
  if (p === 'darwin') return 'macos-x64'
  if (p === 'linux') return 'linux-x64'
  if (p === 'win32') return 'win-x64'
  throw new Error(`Unsupported platform ${p}/${a}`)
}

function resolveTargets() {
  const arg = process.argv.slice(2).find((a) => !a.startsWith('-'))
  const raw = arg || process.env.RETRYSIGHT_DIST_TARGETS || 'current'
  if (raw === 'all') return Object.keys(ALL_TARGETS)
  if (raw === 'current') return [currentTargetKey()]
  return raw.split(',').map((s) => s.trim()).filter(Boolean)
}

console.log('→ Typecheck / build manager')
run(process.execPath, [managerTscBin()], { cwd: managerDir })

console.log('→ Bundle for packaging')
run(process.execPath, [join(root, 'scripts/build-bundle.mjs')], { cwd: root })

const targets = resolveTargets()
for (const key of targets) {
  if (!ALL_TARGETS[key]) throw new Error(`Unknown target: ${key}`)
}
mkdirSync(releaseDir, { recursive: true })

let pkgBin
try {
  pkgBin = require.resolve('@yao-pkg/pkg/lib-es5/bin.js')
} catch {
  pkgBin = null
}

for (const key of targets) {
  const t = ALL_TARGETS[key]
  const dest = join(releaseDir, key)
  rmSync(dest, { recursive: true, force: true })
  mkdirSync(dest, { recursive: true })

  const binaryOut = join(dest, t.bin)
  console.log(`→ pkg ${key} (${t.pkg})`)
  if (!pkgBin) throw new Error('@yao-pkg/pkg not installed — run npm install')

  run(process.execPath, [
    pkgBin,
    join(outDir, 'retrysight-lite.cjs'),
    '--targets',
    t.pkg,
    '--output',
    binaryOut,
    '--compress',
    'GZip',
    '--options',
    'experimental-sqlite',
  ], { cwd: root })

  if (!key.startsWith('win')) {
    try {
      chmodSync(binaryOut, 0o755)
    } catch {
      /* ignore */
    }
  }

  // Ship install helpers beside the binary
  const scripts = {
    'macos-arm64': 'install-macos.sh',
    'macos-x64': 'install-macos.sh',
    'linux-x64': 'install-linux.sh',
    'win-x64': 'install-windows.ps1',
  }
  const installScript = scripts[key]
  copyFileSync(join(root, 'scripts', installScript), join(dest, installScript))
  if (!key.startsWith('win')) chmodSync(join(dest, installScript), 0o755)

  writeFileSync(
    join(dest, 'README.txt'),
    [
      `RetrySightLite ${key}`,
      '',
      'Binary: ' + t.bin,
      '',
      key.startsWith('win')
        ? 'Install:  powershell -ExecutionPolicy Bypass -File .\\install-windows.ps1'
        : `Install:  ./` + installScript,
      '',
      'Default bind: 127.0.0.1:18081',
      'Admin token:  $PREFIX/data/admin-token (auto-generated)',
      'Agent API key: $PREFIX/data/agent-api-key (auto-generated; for optional HTTP ingest)',
      '',
    ].join('\n'),
  )

  // Archive
  const archiveBase = join(releaseDir, `retrysight-lite-${key}`)
  if (t.archive === 'tar') {
    const tarPath = `${archiveBase}.tar.gz`
    rmSync(tarPath, { force: true })
    execFileSync('tar', ['-czf', tarPath, '-C', releaseDir, key], { stdio: 'inherit' })
    console.log(`  archived ${tarPath}`)
  } else {
    // zip via best-effort; on macOS use zip
    const zipPath = `${archiveBase}.zip`
    rmSync(zipPath, { force: true })
    try {
      execFileSync('zip', ['-r', zipPath, key], { cwd: releaseDir, stdio: 'inherit' })
      console.log(`  archived ${zipPath}`)
    } catch {
      console.warn('  zip not available — folder left unarchived in release/' + key)
    }
  }
}

// Also copy a portable "node dist" fallback package for current platform
const portable = join(releaseDir, `portable-${currentTargetKey()}`)
rmSync(portable, { recursive: true, force: true })
mkdirSync(join(portable, 'manager'), { recursive: true })
cpSync(join(root, 'manager/dist'), join(portable, 'manager/dist'), { recursive: true })
cpSync(join(root, 'manager/package.json'), join(portable, 'manager/package.json'))
writeFileSync(
  join(portable, 'run.sh'),
  `#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
export NODE_OPTIONS="\${NODE_OPTIONS:-} --experimental-sqlite"
cd "$DIR/manager"
if [[ ! -d node_modules ]]; then npm install --omit=dev; fi
exec node dist/index.js "$@"
`,
)
try {
  chmodSync(join(portable, 'run.sh'), 0o755)
} catch {
  /* Windows */
}

console.log('\nArtifacts in release/:')
for (const key of targets) {
  console.log(`  - release/${key}/`)
  console.log(`  - release/retrysight-lite-${key}.tar.gz (or .zip)`)
}
console.log(`  - release/portable-${currentTargetKey()}/ (Node 22.5+ fallback)`)
