#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

/**
 * Build self-contained Flutter desktop apps with the pkg backend embedded.
 *
 * Usage:
 *   node scripts/bundle-app.mjs [target]
 *
 * Targets:
 *   current          — host platform (default)
 *   all              — every target buildable on this host
 *   macos-arm64, macos-x64, linux-x64, win-x64
 *   comma-separated  — e.g. macos-arm64,linux-x64
 *
 * Cross-host notes:
 *   - Linux from macOS: uses Docker (linux/amd64) when Docker is available
 *   - Windows: requires a Windows host or GitHub Actions (release-desktop.yml)
 *
 * Output: release/app-<target>/ and release/retrysight-lite-app-<target>.*
 */

import { execFileSync, spawnSync } from 'node:child_process'
import {
  chmodSync,
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { arch, platform } from 'node:os'
import { run } from './run.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const appDir = join(root, 'app')
const releaseDir = join(root, 'release')
const appVersion = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version

const ALL_TARGETS = ['macos-arm64', 'macos-x64', 'linux-x64', 'win-x64']

function currentTargetKey() {
  const p = platform()
  const a = arch()
  if (p === 'darwin' && a === 'arm64') return 'macos-arm64'
  if (p === 'darwin') return 'macos-x64'
  if (p === 'linux') return 'linux-x64'
  if (p === 'win32') return 'win-x64'
  throw new Error(`Unsupported platform ${p}/${a}`)
}

function targetsForHost() {
  const host = platform()
  const list = []
  if (host === 'darwin') {
    list.push(arch() === 'arm64' ? 'macos-arm64' : 'macos-x64')
    if (commandExists('docker')) list.push('linux-x64')
  } else if (host === 'linux') {
    list.push('linux-x64')
  } else if (host === 'win32') {
    list.push('win-x64')
  }
  return list
}

function resolveTargets() {
  const arg = process.argv.slice(2).find((a) => !a.startsWith('-'))
  const raw = arg || process.env.RETRYSIGHT_APP_TARGET || 'current'
  if (raw === 'current') return [currentTargetKey()]
  if (raw === 'all') return targetsForHost()
  return raw.split(',').map((s) => s.trim()).filter(Boolean)
}

function commandExists(cmd) {
  const which = platform() === 'win32' ? 'where' : 'which'
  const r = spawnSync(which, [cmd], {
    stdio: 'ignore',
    shell: platform() === 'win32',
  })
  return r.status === 0
}

function flutterHostFor(target) {
  if (target.startsWith('macos')) return 'darwin'
  if (target === 'linux-x64') return 'linux'
  if (target === 'win-x64') return 'win32'
  throw new Error(`Unknown target: ${target}`)
}

function flutterBuildArgs(target) {
  switch (target) {
    case 'macos-arm64':
    case 'macos-x64':
      return ['build', 'macos', '--release']
    case 'linux-x64':
      return ['build', 'linux', '--release']
    case 'win-x64':
      return ['build', 'windows', '--release']
    default:
      throw new Error(`No Flutter build for ${target}`)
  }
}

function buildFlutterApp(target) {
  const host = platform()
  const required = flutterHostFor(target)

  if (required === host) {
    console.log('→ Build Flutter desktop app')
    run('flutter', flutterBuildArgs(target), { cwd: appDir })
    return
  }

  if (target === 'linux-x64') {
    if (!commandExists('docker')) {
      throw new Error(
        'Linux Flutter builds from macOS require Docker.\n' +
          'Install Docker Desktop, or build on Linux / GitHub Actions:\n' +
          '  gh workflow run release-desktop.yml -f target=linux-x64',
      )
    }
    console.log('→ Build Flutter desktop app (Docker linux/amd64)')
    const flutterImage =
      process.env.FLUTTER_DOCKER_IMAGE || 'ghcr.io/cirruslabs/flutter:stable'
    const uid = typeof process.getuid === 'function' ? process.getuid() : 0
    const gid = typeof process.getgid === 'function' ? process.getgid() : 0
    run('docker', [
      'run',
      '--rm',
      '--platform',
      'linux/amd64',
      '--user',
      'root',
      '-v',
      `${root}:/workspace`,
      '-w',
      '/workspace/app',
      '-e',
      `HOST_UID=${uid}`,
      '-e',
      `HOST_GID=${gid}`,
      flutterImage,
      'bash',
      '-lc',
      [
        'set -euo pipefail',
        'flutter config --enable-linux-desktop',
        'apt-get update -qq',
        'apt-get install -y -qq clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev >/dev/null',
        'flutter pub get',
        'flutter build linux --release',
        'chown -R "${HOST_UID}:${HOST_GID}" /workspace/app/build /workspace/app/.dart_tool 2>/dev/null || true',
      ].join(' && '),
    ])
    return
  }

  if (target === 'win-x64') {
    throw new Error(
      [
        'Windows Flutter builds require a Windows host.',
        'Options:',
        '  1. On Windows: npm run dist:app:win',
        '  2. GitHub Actions: gh workflow run release-desktop.yml -f target=win-x64',
      ].join('\n'),
    )
  }

  throw new Error(
    `${target} Flutter builds require a ${required} host (current: ${host}).`,
  )
}

function appBundleDir(target) {
  switch (target) {
    case 'macos-arm64':
    case 'macos-x64':
      return join(appDir, 'build/macos/Build/Products/Release/RetrySight Lite.app')
    case 'linux-x64':
      return join(appDir, 'build/linux/x64/release/bundle')
    case 'win-x64':
      return join(appDir, 'build/windows/x64/runner/Release')
    default:
      throw new Error(`No app bundle path for ${target}`)
  }
}

function embedBinaryPath(target, bundleDir) {
  const binName = target.startsWith('win') ? 'retrysight-lite.exe' : 'retrysight-lite'
  switch (target) {
    case 'macos-arm64':
    case 'macos-x64':
      return join(bundleDir, 'Contents/Resources', binName)
    case 'linux-x64':
    case 'win-x64':
      return join(bundleDir, binName)
    default:
      throw new Error(`No embed path for ${target}`)
  }
}

function archiveRelease(target, outDir) {
  const versionedBase = join(releaseDir, `retrysight-lite-${appVersion}-${target}`)
  const legacyBase = join(releaseDir, `retrysight-lite-app-${target}`)

  if (target.startsWith('macos') && platform() === 'darwin') {
    const appPath = join(outDir, 'RetrySight Lite.app')
    const dmgPath = `${versionedBase}.dmg`
    rmSync(dmgPath, { force: true })
    try {
      execFileSync('hdiutil', [
        'create',
        '-volname',
        'RetrySight Lite',
        '-srcfolder',
        appPath,
        '-ov',
        '-format',
        'UDZO',
        dmgPath,
      ], { stdio: 'inherit' })
      console.log(`→ DMG ${dmgPath}`)
    } catch {
      console.warn('hdiutil failed — DMG not created (tar.gz still available)')
    }
  }

  if (target.startsWith('win')) {
    const zipPath = `${versionedBase}.zip`
    const legacyZip = `${legacyBase}.zip`
    rmSync(zipPath, { force: true })
    rmSync(legacyZip, { force: true })
    if (commandExists('zip')) {
      execFileSync('zip', ['-r', zipPath, `app-${target}`], {
        cwd: releaseDir,
        stdio: 'inherit',
      })
      copyFileSync(zipPath, legacyZip)
      console.log(`→ Archived ${zipPath}`)
      return
    }
    if (platform() === 'win32') {
      execFileSync(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          `Compress-Archive -Path '${outDir.replace(/'/g, "''")}' -DestinationPath '${zipPath.replace(/'/g, "''")}' -Force`,
        ],
        { stdio: 'inherit' },
      )
      copyFileSync(zipPath, legacyZip)
      console.log(`→ Archived ${zipPath}`)
      return
    }
    console.warn('zip not available — folder left unarchived')
    return
  }

  const tarPath = `${versionedBase}.tar.gz`
  const legacyTar = `${legacyBase}.tar.gz`
  rmSync(tarPath, { force: true })
  rmSync(legacyTar, { force: true })
  execFileSync('tar', ['-czf', tarPath, '-C', releaseDir, `app-${target}`], {
    stdio: 'inherit',
  })
  copyFileSync(tarPath, legacyTar)
  console.log(`→ Archived ${tarPath}`)
}

function finalizeRelease() {
  console.log('\n→ Generate manifest.json')
  run(process.execPath, [join(root, 'scripts/generate-manifest.mjs'), appVersion], { cwd: root })
  run(process.execPath, [join(root, 'scripts/write-cdn-staging.mjs'), appVersion], { cwd: root })
}

function buildTarget(target) {
  if (!ALL_TARGETS.includes(target)) {
    throw new Error(`Unknown target: ${target} (expected one of ${ALL_TARGETS.join(', ')})`)
  }

  const binName = target.startsWith('win') ? 'retrysight-lite.exe' : 'retrysight-lite'
  const pkgBinary = join(releaseDir, target, binName)

  console.log(`\n=== ${target} ===`)
  console.log('→ Build backend binary (pkg)')
  run(process.execPath, [join(root, 'scripts/dist.mjs'), target], { cwd: root })

  if (!existsSync(pkgBinary)) {
    throw new Error(`Backend binary missing: ${pkgBinary}`)
  }

  buildFlutterApp(target)

  const bundleDir = appBundleDir(target)
  if (!existsSync(bundleDir)) {
    throw new Error(`Flutter bundle missing: ${bundleDir}`)
  }

  const embedDest = embedBinaryPath(target, bundleDir)
  mkdirSync(dirname(embedDest), { recursive: true })
  copyFileSync(pkgBinary, embedDest)
  if (!target.startsWith('win')) {
    try {
      chmodSync(embedDest, 0o755)
    } catch {
      /* ignore */
    }
  }
  console.log(`→ Embedded backend: ${embedDest}`)

  const outDir = join(releaseDir, `app-${target}`)
  rmSync(outDir, { recursive: true, force: true })
  mkdirSync(outDir, { recursive: true })

  if (target.startsWith('macos')) {
    cpSync(bundleDir, join(outDir, 'RetrySight Lite.app'), { recursive: true })
  } else if (target === 'linux-x64') {
    cpSync(bundleDir, join(outDir, 'bundle'), { recursive: true })
  } else {
    cpSync(bundleDir, join(outDir, 'RetrySight Lite'), { recursive: true })
  }

  const installHint =
    target === 'linux-x64'
      ? 'Run: ./bundle/retrysightlite\n(No Node.js required — backend is bundled.)'
      : target.startsWith('macos')
        ? 'Open RetrySight Lite.app\n(No Node.js required — backend is bundled.)'
        : 'Run RetrySight Lite\\retrysightlite.exe\n(No Node.js required — backend is bundled.)'

  writeFileSync(
    join(outDir, 'README.txt'),
    [
      `RetrySight Lite desktop app (${target})`,
      '',
      installHint,
      '',
      'Data directory (auto-created on first run):',
      '  macOS:   ~/Library/Application Support/RetrySightLite/data',
      '  Linux:   ~/.local/share/RetrySightLite/data',
      '  Windows: %LOCALAPPDATA%\\RetrySightLite\\data',
      '',
    ].join('\n'),
  )

  archiveRelease(target, outDir)
  console.log(`Done: release/app-${target}/`)
}

const targets = resolveTargets()
const failures = []

for (const target of targets) {
  try {
    buildTarget(target)
  } catch (err) {
    failures.push({ target, err })
    console.error(`\n✗ ${target}: ${err.message}`)
  }
}

if (failures.length > 0) {
  if (failures.length === targets.length) {
    process.exit(1)
  }
  console.warn(`\nCompleted with ${failures.length} failure(s).`)
  for (const { target } of failures) {
    console.warn(`  - ${target}`)
  }
}

if (targets.length > 1) {
  console.log('\nBuild summary:')
  for (const target of targets) {
    const ok = !failures.some((f) => f.target === target)
    console.log(`  ${ok ? '✓' : '✗'} ${target}`)
  }
}

if (failures.length < targets.length) {
  finalizeRelease()
}
