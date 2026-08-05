#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { spawnSync } from 'node:child_process'
import { platform } from 'node:os'

/**
 * Cross-platform command runner.
 * Uses shell on Windows so npm.cmd / flutter.bat resolve correctly.
 */
export function run(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, {
    stdio: 'inherit',
    shell: platform() === 'win32',
    ...opts,
  })
  if (r.error) {
    throw new Error(`${cmd} ${args.join(' ')} failed to start: ${r.error.message}`)
  }
  if (r.status !== 0) {
    const detail = r.status ?? r.signal ?? 'unknown'
    throw new Error(`${cmd} ${args.join(' ')} failed (${detail})`)
  }
}
