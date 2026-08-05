// SPDX-License-Identifier: Apache-2.0

import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs'
import { homedir, hostname, userInfo } from 'node:os'
import { randomBytes } from 'node:crypto'
import { dirname, join, normalize, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')

function legacyEnvName(name: string): string | undefined {
  if (!name.startsWith('RETRYSIGHT_')) return undefined
  return `RETRYSITELITE_${name.slice('RETRYSIGHT_'.length)}`
}

function env(name: string, fallback: string): string {
  const direct = process.env[name]?.trim()
  if (direct) return direct
  const legacy = legacyEnvName(name)
  if (legacy) {
    const fromLegacy = process.env[legacy]?.trim()
    if (fromLegacy) return fromLegacy
  }
  return fallback
}

function envBool(name: string, fallback: boolean): boolean {
  let v = process.env[name]?.trim().toLowerCase()
  if (v == null || v === '') {
    const legacy = legacyEnvName(name)
    if (legacy) v = process.env[legacy]?.trim().toLowerCase()
  }
  if (v == null || v === '') return fallback
  return v === '1' || v === 'true' || v === 'yes' || v === 'on'
}

const WEAK_AGENT_KEYS = new Set(['', 'dev-agent-key', 'changeme', 'password', 'secret'])
const WEAK_ADMIN_TOKENS = new Set(['', 'dev', 'dev-token', 'changeme', 'password', 'secret', 'admin', 'admin-token', 'retrysight-lite'])

function readPersistedSecret(filePath: string): string | undefined {
  if (!existsSync(filePath)) return undefined
  const value = readFileSync(filePath, 'utf8').trim()
  return value || undefined
}

function writePersistedSecret(filePath: string, value: string): void {
  writeFileSync(filePath, `${value}\n`, { encoding: 'utf8', mode: 0o600 })
}

function resolveAgentApiKey(dataDir: string): { key: string; source: string } {
  const keyFile = join(dataDir, 'agent-api-key')
  const fromEnv = process.env.AGENT_API_KEY?.trim()

  if (fromEnv && !WEAK_AGENT_KEYS.has(fromEnv)) {
    return { key: fromEnv, source: 'env' }
  }

  const persisted = readPersistedSecret(keyFile)
  if (persisted) {
    if (fromEnv && WEAK_AGENT_KEYS.has(fromEnv)) {
      console.warn(
        `[retrysight-lite] Ignoring weak AGENT_API_KEY=${JSON.stringify(fromEnv)}; using ${keyFile}`,
      )
    }
    return { key: persisted, source: keyFile }
  }

  const generated = `asl_${randomBytes(24).toString('hex')}`
  writePersistedSecret(keyFile, generated)
  console.log(`[retrysight-lite] Agent API key written to ${keyFile}`)
  return { key: generated, source: keyFile }
}

function resolveAdminToken(dataDir: string): { token: string; source: string } {
  const tokenFile = join(dataDir, 'admin-token')
  const fromEnv =
    process.env.RETRYSIGHT_ADMIN_TOKEN?.trim() ||
    process.env.RETRYSITELITE_ADMIN_TOKEN?.trim()

  if (fromEnv && !WEAK_ADMIN_TOKENS.has(fromEnv) && fromEnv.length >= 16) {
    return { token: fromEnv, source: 'env' }
  }
  if (fromEnv) {
    console.warn(
      `[retrysight-lite] Ignoring weak/short admin token env; using ${tokenFile}`,
    )
  }

  const persisted = readPersistedSecret(tokenFile)
  if (persisted) {
    return { token: persisted, source: tokenFile }
  }

  const generated = `adm_${randomBytes(24).toString('hex')}`
  writePersistedSecret(tokenFile, generated)
  console.log(`[retrysight-lite] Admin token written to ${tokenFile}`)
  return { token: generated, source: tokenFile }
}

function splitPaths(raw: string | undefined): string[] {
  if (!raw?.trim()) return []
  return raw
    .split(/[:;]/)
    .map((p) => p.trim())
    .filter(Boolean)
}

const dataDir = resolve(env('RETRYSIGHT_DATA_DIR', join(root, 'data')))
mkdirSync(dataDir, { recursive: true, mode: 0o700 })
try { chmodSync(dataDir, 0o700) } catch { /* best effort */ }

const collectorDataDir = resolve(
  env('RETRYSIGHT_COLLECTOR_DIR', join(homedir(), '.retrysight-lite')),
)
mkdirSync(collectorDataDir, { recursive: true, mode: 0o700 })
try { chmodSync(collectorDataDir, 0o700) } catch { /* best effort */ }

const agentKey = resolveAgentApiKey(dataDir)
const admin = resolveAdminToken(dataDir)

const osUser = (() => {
  try {
    return userInfo().username
  } catch {
    return 'local'
  }
})()

export const config = {
  /** Default loopback — set RETRYSIGHT_HOST=0.0.0.0 to bind LAN intentionally. */
  host: env('RETRYSIGHT_HOST', '127.0.0.1'),
  port: Number(env('RETRYSIGHT_PORT', '18081')),
  publicUrl: env('RETRYSIGHT_PUBLIC_URL', 'http://127.0.0.1:18081'),
  dataDir,
  dbPath: resolve(env('RETRYSIGHT_DB_PATH', join(dataDir, 'retrysight-lite.db'))),
  agentApiKey: agentKey.key,
  agentApiKeySource: agentKey.source,
  adminToken: admin.token,
  adminTokenSource: admin.source,
  staleAgentSeconds: Number(env('STALE_AGENT_SECONDS', '120')),
  graphqlDev: envBool('RETRYSIGHT_GRAPHQL_DEV', false),
  bodyLimitBytes: Number(env('RETRYSIGHT_BODY_LIMIT', String(1_048_576))),
  /** TLS: set RETRYSIGHT_TLS_CERT and RETRYSIGHT_TLS_KEY to enable HTTPS. */
  tlsCertPath: (() => {
    const p = env('RETRYSIGHT_TLS_CERT', '')
    return p ? resolve(p) : ''
  })(),
  tlsKeyPath: (() => {
    const p = env('RETRYSIGHT_TLS_KEY', '')
    return p ? resolve(p) : ''
  })(),
  tlsEnabled: !!(env('RETRYSIGHT_TLS_CERT', '') && env('RETRYSIGHT_TLS_KEY', '')),
  /** Data retention: auto-delete tasks/events older than N days (0 = never). */
  retentionDays: Number(env('RETRYSIGHT_RETENTION_DAYS', '0')),
  retentionIntervalMs: Number(env('RETRYSIGHT_RETENTION_INTERVAL_MS', String(86_400_000))),
  /** In-process IDE log collectors (default on). Set RETRYSIGHT_COLLECTORS=0 to disable. */
  collectorsEnabled: envBool('RETRYSIGHT_COLLECTORS', true),
  collectorDataDir,
  agentName: env('RETRYSIGHT_AGENT_NAME', `local-${hostname()}`),
  agentEmail: env('RETRYSIGHT_EMAIL', `${osUser}@local`),
  pollIntervalMs: Number(env('RETRYSIGHT_POLL_MS', '5000')),
  flushIntervalMs: Number(env('RETRYSIGHT_FLUSH_MS', '10000')),
  cursorEnabled: envBool('RETRYSIGHT_CURSOR', true),
  claudeEnabled: envBool('RETRYSIGHT_CLAUDE', true),
  warpEnabled: envBool('RETRYSIGHT_WARP', true),
  windsurfEnabled: envBool('RETRYSIGHT_WINDSURF', true),
  clineEnabled: envBool('RETRYSIGHT_CLINE', true),
  aiderEnabled: envBool('RETRYSIGHT_AIDER', true),
  continueEnabled: envBool('RETRYSIGHT_CONTINUE', true),
  copilotEnabled: envBool('RETRYSIGHT_COPILOT', true),
  cursorWatchPaths: splitPaths(env('RETRYSIGHT_CURSOR_PATHS', '')),
  claudeWatchPaths: splitPaths(env('RETRYSIGHT_CLAUDE_PATHS', '')),
  warpWatchPaths: splitPaths(env('RETRYSIGHT_WARP_PATHS', '')),
  windsurfWatchPaths: splitPaths(env('RETRYSIGHT_WINDSURF_PATHS', '')),
  clineWatchPaths: splitPaths(env('RETRYSIGHT_CLINE_PATHS', '')),
  aiderWatchPaths: splitPaths(env('RETRYSIGHT_AIDER_PATHS', '')),
  continueWatchPaths: splitPaths(env('RETRYSIGHT_CONTINUE_PATHS', '')),
  copilotWatchPaths: splitPaths(env('RETRYSIGHT_COPILOT_PATHS', '')),
}

mkdirSync(dirname(config.dbPath), { recursive: true, mode: 0o700 })
