// SPDX-License-Identifier: Apache-2.0

import { config } from './config.js'
import { createServer } from './server.js'
import { startCollectors, stopCollectors } from './collectors/runtime.js'
import { startTui } from './tui.js'

async function main() {
  // Default-created files (DB, WAL, buffer.jsonl, offsets.json) must be private.
  process.umask(0o077)
  const headless =
    process.env.RETRYSIGHT_HEADLESS === '1' ||
    process.env.RETRYSITELITE_HEADLESS === '1' ||
    process.argv.includes('--headless')
  const app = await createServer()
  await app.listen({ host: config.host, port: config.port })

  startCollectors()

  const shutdown = async () => {
    stopCollectors()
    try {
      await app.close()
    } catch {
      /* ignore */
    }
    process.exit(0)
  }
  process.on('SIGINT', () => void shutdown())
  process.on('SIGTERM', () => void shutdown())

  if (headless) {
    console.log(`RetrySight Lite on http://${config.host}:${config.port}`)
    console.log(`  GraphQL /graphql · dashboard /api/v1/dashboard · ingest /api/v1/ingest/*`)
    console.log(`  Admin: Authorization: Bearer $RETRYSIGHT_ADMIN_TOKEN (see ${config.adminTokenSource})`)
    if (config.host !== '127.0.0.1' && config.host !== 'localhost') {
      console.warn(
        `[retrysight-lite] Listening on ${config.host} — LAN reachable. Prefer 127.0.0.1 unless intentional.`,
      )
    }
    return
  }

  startTui(config.port)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
