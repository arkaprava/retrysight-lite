// SPDX-License-Identifier: Apache-2.0

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { hostname, userInfo } from 'node:os'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { config } from '../config.js'
import { getDb, nowIso } from '../db.js'
import { completeStaleTasks, processBatch, registerOrResolveAgent } from '../ingest.js'
import { EventBuffer } from './event-buffer.js'
import { FlexibleLogCollector, type CollectorConfig, type LogFormat } from './flexible-collector.js'
import { WarpSqliteCollector } from './warp-sqlite.js'
import { ClaudeCollector } from './claude-collector.js'
import { CursorSqliteCollector } from './cursor-sqlite.js'

export type CollectorRuntimeStatus = {
  enabled: boolean
  running: boolean
  agentId: string | null
  collectors: string[]
  roots: Record<string, string[]>
  lastPollAt: string | null
  lastFlushAt: string | null
  lastError: string | null
}

let status: CollectorRuntimeStatus = {
  enabled: false,
  running: false,
  agentId: null,
  collectors: [],
  roots: {},
  lastPollAt: null,
  lastFlushAt: null,
  lastError: null,
}

const SETTINGS_KEY = 'collector_configs'

export interface ToolCollectorConfig {
  filePattern: string
  format: LogFormat
}

export type CollectorConfigMap = Record<string, ToolCollectorConfig>

const DEFAULT_CONFIGS: CollectorConfigMap = {
  CURSOR: { filePattern: '*.jsonl', format: 'jsonl' },
  CLAUDE_CODE: { filePattern: '*.jsonl', format: 'jsonl' },
  WARP: { filePattern: '*.log', format: 'plaintext' },
  WINDSURF: { filePattern: '*.jsonl', format: 'jsonl' },
  CLINE: { filePattern: '*.jsonl', format: 'jsonl' },
  AIDER: { filePattern: '*.jsonl', format: 'jsonl' },
  CONTINUE: { filePattern: '*.jsonl', format: 'jsonl' },
  GITHUB_COPILOT: { filePattern: '*.jsonl', format: 'jsonl' },
}

const ALLOWED_COLLECTOR_TOOLS = new Set([
  'CURSOR',
  'CLAUDE_CODE',
  'WARP',
  'WINDSURF',
  'CLINE',
  'AIDER',
  'CONTINUE',
  'GITHUB_COPILOT',
])

/** Validate a collector config map: allowlist tool keys, format enum, bounded filePattern. */
export function sanitizeCollectorConfigMap(input: unknown): CollectorConfigMap | null {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) return null
  const out: CollectorConfigMap = {}
  for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
    if (!ALLOWED_COLLECTOR_TOOLS.has(key)) return null
    if (typeof value !== 'object' || value === null) return null
    const v = value as Record<string, unknown>
    if (v.format !== 'jsonl' && v.format !== 'plaintext') return null
    if (typeof v.filePattern !== 'string' || v.filePattern.length > 128) return null
    out[key] = { filePattern: v.filePattern, format: v.format }
  }
  return out
}

// Common interface for all collectors that can be polled
interface Collector {
  poll(): void
}

let pollTimer: ReturnType<typeof setInterval> | null = null
let flushTimer: ReturnType<typeof setInterval> | null = null
let collectors: Collector[] = []
let buffer: EventBuffer | null = null
let collectorNames: string[] = []

function expandHome(p: string): string {
  if (p === '~') return homedir()
  if (p.startsWith('~/') || p.startsWith('~\\')) return join(homedir(), p.slice(2))
  return p
}

export function loadCollectorConfigs(): CollectorConfigMap {
  try {
    const db = getDb()
    const row = db
      .prepare('SELECT value FROM settings WHERE key = ?')
      .get(SETTINGS_KEY) as { value: string } | undefined
    if (row?.value) {
      const parsed = JSON.parse(row.value) as CollectorConfigMap
      const sanitized = sanitizeCollectorConfigMap(parsed)
      // Merge with defaults so new tools get sensible values
      if (sanitized) return { ...DEFAULT_CONFIGS, ...sanitized }
    }
  } catch {
    // settings table or query may not exist yet
  }
  return { ...DEFAULT_CONFIGS }
}

export function saveCollectorConfigs(map: CollectorConfigMap): void {
  const sanitized = sanitizeCollectorConfigMap(map)
  if (!sanitized) throw new Error('Invalid collector config')
  const db = getDb()
  db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)')
    .run(SETTINGS_KEY, JSON.stringify(sanitized))
}

export function getCollectorConfigs(): CollectorConfigMap {
  return loadCollectorConfigs()
}

/** Look for warp.sqlite inside any of the given root directories (1 level deep). */
function findWarpSqlite(roots: string[]): string | null {
  for (const root of roots) {
    const candidate = join(root, 'warp.sqlite')
    if (existsSync(candidate)) return candidate
  }
  return null
}

/** Look for Cursor's AI-code-tracking DB inside any of the given root directories. */
function findCursorAiTrackingDb(roots: string[]): string | null {
  for (const root of roots) {
    const candidate = join(root, 'ai-tracking', 'ai-code-tracking.db')
    if (existsSync(candidate)) return candidate
  }
  return null
}

function existingPaths(configured: string[], defaults: string[]): string[] {
  const fromConfig = configured.map(expandHome).filter((p) => existsSync(p))
  if (fromConfig.length) return fromConfig
  return defaults.map(expandHome).filter((p) => existsSync(p))
}

function defaultCursorPaths(): string[] {
  const home = homedir()
  return [
    join(home, 'Library', 'Application Support', 'Cursor', 'User', 'workspaceStorage'),
    join(home, 'Library', 'Application Support', 'Cursor', 'logs'),
    join(home, '.cursor'),
    join(home, 'AppData', 'Roaming', 'Cursor', 'User', 'workspaceStorage'),
    join(home, '.config', 'Cursor', 'User', 'workspaceStorage'),
  ]
}

function defaultClaudePaths(): string[] {
  const home = homedir()
  return [
    join(home, '.claude'),
    join(home, '.config', 'claude-code'),
    join(home, 'Library', 'Application Support', 'Claude'),
    join(home, 'Library', 'Application Support', 'Claude', 'IndexedDB'),
    join(home, 'AppData', 'Roaming', 'Claude'),
    join(home, 'AppData', 'Roaming', 'Claude', 'IndexedDB'),
  ]
}

function defaultWarpPaths(): string[] {
  const home = homedir()
  return [
    // Warp v2025+ macOS sandboxed location (Group Containers)
    join(home, 'Library', 'Group Containers', '2BBY89MBSN.dev.warp', 'Library', 'Application Support', 'dev.warp.Warp-Stable'),
    // Warp v2025+ macOS location
    join(home, 'Library', 'Application Support', 'dev.warp.Warp-Stable'),
    join(home, 'Library', 'Application Support', 'dev.warp.Warp-Stable', 'mcp'),
    // Legacy paths
    join(home, '.warp', 'sessions'),
    join(home, '.oz'),
    join(home, 'Library', 'Application Support', 'com.warp.warp'),
    join(home, '.local', 'share', 'warp', 'sessions'),
  ]
}

function defaultWindsurfPaths(): string[] {
  const home = homedir()
  return [
    join(home, '.windsurf', 'logs'),
    join(home, 'Library', 'Application Support', 'Windsurf', 'logs'),
    join(home, '.config', 'windsurf', 'logs'),
    join(home, 'AppData', 'Roaming', 'Windsurf', 'logs'),
  ]
}

function defaultClinePaths(): string[] {
  const home = homedir()
  return [
    join(home, '.cline', 'sessions'),
    join(home, '.config', 'cline', 'sessions'),
    join(home, 'Library', 'Application Support', 'Cline', 'sessions'),
    join(home, 'AppData', 'Roaming', 'Cline', 'sessions'),
  ]
}

function defaultAiderPaths(): string[] {
  const home = homedir()
  return [
    join(home, '.aider', 'logs'),
    join(home, '.config', 'aider', 'logs'),
    join(home, 'AppData', 'Roaming', 'Aider', 'logs'),
  ]
}

function defaultContinuePaths(): string[] {
  const home = homedir()
  return [
    join(home, '.continue', 'logs'),
    join(home, '.config', 'continue', 'logs'),
    join(home, 'Library', 'Application Support', 'Continue', 'logs'),
    join(home, 'AppData', 'Roaming', 'Continue', 'logs'),
  ]
}

function defaultCopilotPaths(): string[] {
  const home = homedir()
  return [
    join(home, '.copilot-logs'),
    join(home, '.config', 'copilot', 'logs'),
    join(home, 'Library', 'Application Support', 'GitHub', 'Copilot', 'logs'),
    join(home, 'AppData', 'Roaming', 'GitHub', 'Copilot', 'logs'),
  ]
}

function agentIdPath(): string {
  return join(config.collectorDataDir, 'agent-id')
}

function loadAgentId(): string | undefined {
  try {
    const v = readFileSync(agentIdPath(), 'utf8').trim()
    return v || undefined
  } catch {
    return undefined
  }
}

function saveAgentId(id: string): void {
  mkdirSync(config.collectorDataDir, { recursive: true })
  writeFileSync(agentIdPath(), `${id}\n`, { encoding: 'utf8', mode: 0o600 })
}

function heartbeatPayload() {
  let osUsername: string | null = null
  try {
    osUsername = userInfo().username
  } catch {
    osUsername = null
  }
  return {
    name: config.agentName,
    developerEmail: config.agentEmail,
    hostname: hostname() || 'localhost',
    osUsername,
    displayName: null,
    gitEmail: null,
    installedCollectors: collectorNames,
  }
}

function flush(): void {
  if (!buffer) return
  try {
    const { taskStarts, items } = buffer.drain(200)
    const agent = registerOrResolveAgent(loadAgentId(), heartbeatPayload())
    saveAgentId(agent.id)
    status.agentId = agent.id
    if (taskStarts.length || items.length) {
      processBatch(agent.id, {
        heartbeat: heartbeatPayload(),
        taskStarts,
        items,
      })
    }
    completeStaleTasks()
    status.lastFlushAt = new Date().toISOString()
    status.lastError = null
  } catch (err) {
    status.lastError = err instanceof Error ? err.message : String(err)
  }
}

function poll(): void {
  try {
    for (const c of collectors) c.poll()
    status.lastPollAt = new Date().toISOString()
    status.lastError = null
  } catch (err) {
    status.lastError = err instanceof Error ? err.message : String(err)
  }
}

export function getCollectorStatus(): CollectorRuntimeStatus {
  return { ...status, roots: { ...status.roots }, collectors: [...status.collectors] }
}

export function startCollectors(): CollectorRuntimeStatus {
  if (!config.collectorsEnabled) {
    status = {
      ...status,
      enabled: false,
      running: false,
      collectors: [],
      roots: {},
    }
    return getCollectorStatus()
  }

  buffer = new EventBuffer(config.collectorDataDir)
  collectors = []
  collectorNames = []
  const roots: Record<string, string[]> = {}
  const toolConfigs = loadCollectorConfigs()

  function addCollector(
    name: string,
    enabled: boolean,
    envPaths: string[],
    defaultPaths: () => string[],
  ) {
    if (!enabled) return
    const toolName = name
    const tc = toolConfigs[toolName] ?? DEFAULT_CONFIGS[toolName] ?? { filePattern: '*.jsonl', format: 'jsonl' }
    const toolRoots = existingPaths(envPaths, defaultPaths())
    collectors.push(new FlexibleLogCollector(toolName, toolRoots, buffer!, tc))
    collectorNames.push(toolName)
    roots[toolName] = toolRoots
  }

  addCollector('CURSOR', config.cursorEnabled, config.cursorWatchPaths, defaultCursorPaths)

  // CURSOR: SQLite collector for the AI-code-attribution DB, alongside the
  // file-based collector above (which stays as a harmless no-op fallback for
  // any `.jsonl` files an older/different Cursor version might still write).
  if (config.cursorEnabled) {
    const cursorRoots = existingPaths(config.cursorWatchPaths, defaultCursorPaths())
    const cursorDbPath = findCursorAiTrackingDb(cursorRoots)
    if (cursorDbPath) {
      collectors.push(new CursorSqliteCollector('CURSOR', cursorDbPath, buffer!))
      collectorNames.push('CURSOR_SQLITE')
    }
  }

  addCollector('CLAUDE_CODE', config.claudeEnabled, config.claudeWatchPaths, defaultClaudePaths)

  // CLAUDE: dedicated collector for Code CLI config, Desktop LevelDB, and debug logs
  if (config.claudeEnabled) {
    collectors.push(new ClaudeCollector('CLAUDE', buffer!))
    collectorNames.push('CLAUDE')
  }

  // WARP: file-based collector for MCP logs + SQLite collector for conversation/task data
  if (config.warpEnabled) {
    const warpRoots = existingPaths(config.warpWatchPaths, defaultWarpPaths())
    // File-based collector (MCP logs, etc.)
    const warpTc = toolConfigs['WARP'] ?? DEFAULT_CONFIGS['WARP'] ?? { filePattern: '*.log', format: 'plaintext' }
    collectors.push(new FlexibleLogCollector('WARP', warpRoots, buffer!, warpTc))
    collectorNames.push('WARP')
    roots.WARP = warpRoots

    // SQLite collector: look for warp.sqlite in the WARP roots
    const warpDbPath = findWarpSqlite(warpRoots)
    if (warpDbPath) {
      collectors.push(new WarpSqliteCollector('WARP', warpDbPath, buffer!, warpRoots))
      collectorNames.push('WARP_SQLITE')
    }
  }

  addCollector('WINDSURF', config.windsurfEnabled, config.windsurfWatchPaths, defaultWindsurfPaths)
  addCollector('CLINE', config.clineEnabled, config.clineWatchPaths, defaultClinePaths)
  addCollector('AIDER', config.aiderEnabled, config.aiderWatchPaths, defaultAiderPaths)
  addCollector('CONTINUE', config.continueEnabled, config.continueWatchPaths, defaultContinuePaths)
  addCollector('GITHUB_COPILOT', config.copilotEnabled, config.copilotWatchPaths, defaultCopilotPaths)

  try {
    const agent = registerOrResolveAgent(loadAgentId(), heartbeatPayload())
    saveAgentId(agent.id)
    status.agentId = agent.id
  } catch (err) {
    status.lastError = err instanceof Error ? err.message : String(err)
  }

  if (pollTimer) clearInterval(pollTimer)
  if (flushTimer) clearInterval(flushTimer)
  pollTimer = setInterval(poll, config.pollIntervalMs)
  flushTimer = setInterval(flush, config.flushIntervalMs)
  // Unref so timers don't keep the process alive alone if desired; keep referenced for daemon use.
  poll()
  flush()

  status = {
    enabled: true,
    running: true,
    agentId: status.agentId,
    collectors: collectorNames,
    roots,
    lastPollAt: status.lastPollAt,
    lastFlushAt: status.lastFlushAt,
    lastError: status.lastError,
  }
  console.log(
    `[retrysight-lite] Collectors started: ${collectorNames.join(', ') || '(none)'} → ${config.collectorDataDir}`,
  )
  for (const [name, paths] of Object.entries(roots)) {
    console.log(`[retrysight-lite]   ${name} roots: ${paths.length ? paths.join(', ') : '(none found)'}`)
  }
  return getCollectorStatus()
}

export function stopCollectors(): void {
  if (pollTimer) clearInterval(pollTimer)
  if (flushTimer) clearInterval(flushTimer)
  pollTimer = null
  flushTimer = null
  collectors = []
  buffer = null
  status.running = false
}
