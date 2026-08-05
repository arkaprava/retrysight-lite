#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { build } from 'esbuild'
import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const outDir = join(root, 'dist-pkg')
mkdirSync(outDir, { recursive: true })

await build({
  entryPoints: [join(root, 'manager/src/index.ts')],
  outfile: join(outDir, 'retrysight-lite.cjs'),
  bundle: true,
  platform: 'node',
  target: 'node22',
  format: 'cjs',
  sourcemap: false,
  // Keep native/optional peer paths external where needed
  external: [],
  banner: {
    js: '#!/usr/bin/env node\n',
  },
  logLevel: 'info',
})

console.log(`Bundled → ${join(outDir, 'retrysight-lite.cjs')}`)
