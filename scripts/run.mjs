#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { spawnSync } from 'node:child_process'
import { platform } from 'node:os'

const isWin = platform() === 'win32'

/** Map bare command names to Windows executables when needed. */
function resolveCmd(cmd) {
  if (!isWin) return cmd
  if (cmd === 'npm') return 'npm.cmd'
  if (cmd === 'npx') return 'npx.cmd'
  return cmd
}

/**
 * Cross-platform command runner.
 * Resolves npm.cmd on Windows and falls back to shell when needed.
 */
export function run(cmd, args, opts = {}) {
  const resolved = resolveCmd(cmd)
  const r = spawnSync(resolved, args, {
    stdio: 'inherit',
    shell: isWin && resolved === cmd,
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
