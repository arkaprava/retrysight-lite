#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const releaseDir = join(root, 'release')
const version = process.argv[2] || JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version

const staticDir = join(releaseDir, 'cdn-staging')
mkdirSync(join(staticDir, 'latest'), { recursive: true })
mkdirSync(join(staticDir, `v${version}`), { recursive: true })
mkdirSync(join(staticDir, 'lite', 'latest'), { recursive: true })
mkdirSync(join(staticDir, 'lite', `v${version}`), { recursive: true })

for (const name of ['install.sh', 'install.ps1']) {
  const src = join(root, 'scripts', name)
  if (!existsSync(src)) continue
  copyFileSync(src, join(staticDir, name))
  try {
    chmodSync(join(staticDir, name), 0o755)
  } catch {
    /* windows */
  }
}

const manifest = join(releaseDir, 'manifest.json')
if (existsSync(manifest)) {
  for (const dest of [
    'latest/manifest.json',
    `v${version}/manifest.json`,
    'lite/latest/manifest.json',
    `lite/v${version}/manifest.json`,
  ]) {
    copyFileSync(manifest, join(staticDir, dest))
  }
}

const artifacts = [
  `retrysight-lite-${version}-macos-arm64.dmg`,
  `retrysight-lite-${version}-macos-x64.dmg`,
  `retrysight-lite-${version}-linux-x64.tar.gz`,
  `retrysight-lite-${version}-win-x64.zip`,
  'retrysight-lite-app-macos-arm64.tar.gz',
  'retrysight-lite-app-macos-x64.tar.gz',
  'retrysight-lite-app-linux-x64.tar.gz',
  'retrysight-lite-app-win-x64.zip',
]

for (const file of artifacts) {
  const src = join(releaseDir, file)
  if (!existsSync(src)) continue
  for (const dest of [`v${version}/${file}`, `latest/${file}`, `lite/v${version}/${file}`, `lite/latest/${file}`]) {
    copyFileSync(src, join(staticDir, dest))
  }
}

writeFileSync(
  join(staticDir, 'README.txt'),
  [
    'Upload contents to app.retrysight.com (see docs/DOWNLOADS.md)',
    '',
    '  install.sh          → https://app.retrysight.com/install.sh',
    '  lite/latest/        → manifests + artifacts for curl installer',
    '',
  ].join('\n'),
)

console.log(`CDN staging → release/cdn-staging/`)
