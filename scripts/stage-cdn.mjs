#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { execFileSync } from 'node:child_process'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
execFileSync(process.execPath, [join(root, 'scripts/generate-manifest.mjs')], {
  stdio: 'inherit',
})
execFileSync(process.execPath, [join(root, 'scripts/write-cdn-staging.mjs')], {
  stdio: 'inherit',
})
