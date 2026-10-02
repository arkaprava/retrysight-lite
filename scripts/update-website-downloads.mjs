#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
//
// Rewrites the Lite download filenames in retrysight-website's
// src/data/site.ts to point at <version>.
//
// Usage: node scripts/update-website-downloads.mjs <path/to/site.ts> <version>

import { readFileSync, writeFileSync } from 'node:fs'

const [file, version] = process.argv.slice(2)
if (!file || !/^\d+\.\d+\.\d+$/.test(version ?? '')) {
  console.error('usage: update-website-downloads.mjs <site.ts> <x.y.z>')
  process.exit(2)
}

const before = readFileSync(file, 'utf8')
const after = before
  .replace(/retrysight-lite-\d+\.\d+\.\d+-(macos-arm64\.dmg|linux-x64\.tar\.gz|win-x64\.zip)/g, `retrysight-lite-${version}-$1`)
  .replace(/(lite\/latest\/manifest\.json \(v)\d+\.\d+\.\d+(\))/, `$1${version}$2`)

if (after === before) {
  console.log(`site.ts already references ${version}; nothing to change`)
} else {
  writeFileSync(file, after)
  console.log(`Updated ${file} to ${version}`)
}
