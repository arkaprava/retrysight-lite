#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { spawn } from 'node:child_process'
import { createReadStream, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const BUCKET = process.env.R2_BUCKET || 'download-retrysight'
const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const staging = join(root, 'release/cdn-staging')

const UPLOADS = [
  { key: 'install.sh', file: join(staging, 'install.sh'), contentType: 'text/plain; charset=utf-8' },
  { key: 'install.ps1', file: join(staging, 'install.ps1'), contentType: 'text/plain; charset=utf-8' },
  { key: 'lite/latest/manifest.json', file: join(staging, 'lite/latest/manifest.json'), contentType: 'application/json' },
  { key: 'lite/latest/retrysight-lite-1.0.0-macos-arm64.dmg', file: join(staging, 'lite/latest/retrysight-lite-1.0.0-macos-arm64.dmg'), contentType: 'application/octet-stream' },
  { key: 'lite/latest/retrysight-lite-1.0.0-linux-x64.tar.gz', file: join(staging, 'lite/latest/retrysight-lite-1.0.0-linux-x64.tar.gz'), contentType: 'application/octet-stream' },
  { key: 'lite/latest/retrysight-lite-1.0.0-win-x64.zip', file: join(staging, 'lite/latest/retrysight-lite-1.0.0-win-x64.zip'), contentType: 'application/octet-stream' },
  { key: 'lite/latest/retrysight-lite-app-macos-arm64.tar.gz', file: join(staging, 'lite/latest/retrysight-lite-app-macos-arm64.tar.gz'), contentType: 'application/octet-stream' },
  { key: 'lite/latest/retrysight-lite-app-linux-x64.tar.gz', file: join(staging, 'lite/latest/retrysight-lite-app-linux-x64.tar.gz'), contentType: 'application/octet-stream' },
  { key: 'lite/latest/retrysight-lite-app-win-x64.zip', file: join(staging, 'lite/latest/retrysight-lite-app-win-x64.zip'), contentType: 'application/octet-stream' },
]

function fmtBytes(n) {
  if (n >= 1e9) return `${(n / 1e9).toFixed(1)} GB`
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)} MB`
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)} KB`
  return `${n} B`
}

function upload({ key, file, contentType }) {
  const size = statSync(file).size
  const objectPath = `${BUCKET}/${key}`
  const usePipe = size < 64 * 1024 // small scripts via pipe

  return new Promise((resolve, reject) => {
    const args = [
      'wrangler', 'r2', 'object', 'put', objectPath,
      '--content-type', contentType,
      '--remote',
    ]
    if (usePipe) args.push('--pipe')
    else args.push('--file', file)

    const child = spawn('npx', args, { stdio: usePipe ? ['pipe', 'inherit', 'inherit'] : ['inherit', 'inherit', 'inherit'] })

    if (usePipe) {
      createReadStream(file).pipe(child.stdin)
    }

    let lastPct = -1
    if (!usePipe) {
      const interval = setInterval(() => {
        // wrangler doesn't expose byte progress; show elapsed spinner via timestamp
      }, 5000)
      child.on('close', () => clearInterval(interval))
    }

    child.on('error', reject)
    child.on('close', (code) => {
      if (code === 0) resolve()
      else reject(new Error(`upload failed for ${key} (exit ${code})`))
    })
  })
}

async function main() {
  const totalBytes = UPLOADS.reduce((s, u) => s + statSync(u.file).size, 0)
  console.log(`\nUploading to R2 bucket: ${BUCKET}`)
  console.log(`Files: ${UPLOADS.length}  Total: ${fmtBytes(totalBytes)}\n`)

  const t0 = Date.now()
  for (let i = 0; i < UPLOADS.length; i++) {
    const item = UPLOADS[i]
    const size = statSync(item.file).size
    const started = Date.now()
    console.log(`[${i + 1}/${UPLOADS.length}] ${item.key}  (${fmtBytes(size)})`)
    process.stdout.write('  → uploading…\n')

    await upload(item)

    const elapsed = ((Date.now() - started) / 1000).toFixed(1)
    const speed = size / (Date.now() - started) * 1000
    console.log(`  ✓ done in ${elapsed}s (${fmtBytes(speed)}/s)\n`)
  }

  const totalElapsed = ((Date.now() - t0) / 1000).toFixed(1)
  console.log(`All uploads complete in ${totalElapsed}s`)
  console.log('\nVerify:')
  console.log('  curl -fsSL https://app.retrysight.com/install.sh | head -3')
  console.log('  curl -fsSL https://app.retrysight.com/lite/latest/manifest.json | head -5')
}

main().catch((err) => {
  console.error('\n✗', err.message)
  process.exit(1)
})
