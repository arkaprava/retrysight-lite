#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

/**
 * Write release/manifest.json from built app artifacts + SHA-256 checksums.
 *
 * Usage: node scripts/generate-manifest.mjs [version]
 */

import { createHash } from 'node:crypto'
import { createReadStream, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const releaseDir = join(root, 'release')

const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const version = process.argv[2] || pkg.version
const baseUrl =
  process.env.RETRYSIGHT_DOWNLOAD_BASE?.replace(/\/$/, '') ||
  'https://app.retrysight.com/lite'

const ARTIFACTS = [
  {
    id: 'macos-arm64',
    platform: 'darwin',
    arch: 'arm64',
    primary: `retrysight-lite-${version}-macos-arm64.dmg`,
    fallbacks: [`retrysight-lite-app-macos-arm64.tar.gz`],
    installKind: 'dmg',
  },
  {
    id: 'macos-x64',
    platform: 'darwin',
    arch: 'x64',
    primary: `retrysight-lite-${version}-macos-x64.dmg`,
    fallbacks: [`retrysight-lite-app-macos-x64.tar.gz`],
    installKind: 'dmg',
  },
  {
    id: 'linux-x64',
    platform: 'linux',
    arch: 'x64',
    primary: `retrysight-lite-${version}-linux-x64.tar.gz`,
    fallbacks: [`retrysight-lite-app-linux-x64.tar.gz`],
    installKind: 'tar.gz',
  },
  {
    id: 'win-x64',
    platform: 'win32',
    arch: 'x64',
    primary: `retrysight-lite-${version}-win-x64.zip`,
    fallbacks: [`retrysight-lite-app-win-x64.zip`],
    installKind: 'zip',
  },
]

async function sha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256')
    createReadStream(filePath)
      .on('data', (d) => hash.update(d))
      .on('end', () => resolve(hash.digest('hex')))
      .on('error', reject)
  })
}

function resolveFile(entry) {
  for (const name of [entry.primary, ...entry.fallbacks]) {
    const path = join(releaseDir, name)
    if (existsSync(path)) return { name, path }
  }
  return null
}

const downloads = []
for (const entry of ARTIFACTS) {
  const resolved = resolveFile(entry)
  if (!resolved) continue
  const checksum = await sha256(resolved.path)
  downloads.push({
    id: entry.id,
    platform: entry.platform,
    arch: entry.arch,
    filename: resolved.name,
    url: `${baseUrl}/latest/${resolved.name}`,
    sha256: checksum,
    size: readFileSync(resolved.path).length,
    kind: entry.installKind,
  })
}

const manifest = {
  schema: 1,
  product: 'RetrySight Lite',
  version,
  releasedAt: new Date().toISOString(),
  baseUrl: `${baseUrl}/latest`,
  installScript: `${baseUrl.replace(/\/lite$/, '')}/install.sh`,
  installScriptWindows: `${baseUrl.replace(/\/lite$/, '')}/install.ps1`,
  downloads,
}

const outPath = join(releaseDir, 'manifest.json')
writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`)
console.log(`Wrote ${outPath} (${downloads.length} artifact(s))`)
