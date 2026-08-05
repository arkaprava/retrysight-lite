// SPDX-License-Identifier: Apache-2.0

import { existsSync, readFileSync, readdirSync, statSync, mkdirSync, cpSync } from 'node:fs'
import { join, basename } from 'node:path'
import { homedir, hostname } from 'node:os'
import type { EventBuffer } from './event-buffer.js'

const OFFSET_NS = 'CLAUDE'

interface ClaudeCodeConfig {
  installMethod?: string
  firstStartTime?: string
  userID?: string
  clientDataCache?: { data: unknown; timestamp: number }
}

interface PlanUsageSample {
  t: number // timestamp ms
  u: { fh: number; sd: number } // usage counts
}

interface ProjectClaudeConfig {
  firstStartTime?: string
  opusProMigrationComplete?: boolean
}

/**
 * Unified Claude collector that handles:
 * - Claude Code CLI (via ~/.claude.json config + project .claude/ dirs)
 * - Claude Desktop (via plan-usage-history.json + best-effort LevelDB)
 * - Claude debug logs (~/.claude/debug/*.txt)
 */
export class ClaudeCollector {
  private dbCopyAttempted = false

  constructor(
    private readonly sourceTool: string,
    private readonly buffer: EventBuffer,
  ) {}

  poll(): void {
    this.pollCodeConfig()
    this.pollDebugLogs()
    this.pollDesktopUsage()
    this.pollDesktopLevelDB()
  }

  // ─── Claude Code CLI ─────────────────────────────────────────────

  /** Read ~/.claude.json for metadata and emit a heartbeat-like event. */
  private pollCodeConfig(): void {
    const path = join(homedir(), '.claude.json')
    if (!existsSync(path)) return

    const key = 'claude_code_config_mtime'
    const prev = this.buffer.readOffset(key)
    try {
      const st = statSync(path)
      const mtime = st.mtimeMs
      if (mtime <= prev) return // no change
      this.buffer.writeOffset(key, mtime)

      const raw = readFileSync(path, 'utf8')
      const cfg = JSON.parse(raw) as ClaudeCodeConfig
      if (!cfg.firstStartTime) return

      const taskId = `CLAUDE_CODE:install`
      const startedAt = cfg.firstStartTime || new Date().toISOString()

      this.buffer.offerTaskStart({
        taskId,
        sourceTool: this.sourceTool,
        title: 'Claude Code CLI',
        startedAt,
        projectContext: {
          projectRoot: null,
          repoName: null,
          gitBranch: null,
          gitCommit: null,
          remoteUrl: null,
        },
      })

      this.buffer.offerItem({
        type: 'EVENT',
        taskId,
        eventType: 'SESSION_START',
        occurredAt: startedAt,
        payload: {
          installMethod: cfg.installMethod ?? null,
          userID: cfg.userID ?? null,
          hostname: hostname(),
        },
      })
    } catch {
      // ignore
    }
  }

  // ─── Claude Code Debug Logs ──────────────────────────────────────

  /** Read ~/.claude/debug/*.txt files for recent activity. */
  private pollDebugLogs(): void {
    const debugDir = join(homedir(), '.claude', 'debug')
    if (!existsSync(debugDir)) return

    let entries: string[]
    try {
      entries = readdirSync(debugDir)
    } catch {
      return
    }

    for (const name of entries) {
      if (!name.endsWith('.txt')) continue
      const path = join(debugDir, name)
      this.tailDebugLog(path)
    }
  }

  private tailDebugLog(path: string): void {
    const key = `debug_log:${path}`
    let offset = this.buffer.readOffset(key)
    let size: number
    try {
      size = statSync(path).size
    } catch {
      return
    }
    if (offset > size) offset = 0
    if (offset === size) return

    let text: string
    try {
      const buf = readFileSync(path)
      text = buf.subarray(offset).toString('utf8')
    } catch {
      return
    }

    const sessionId = basename(path).replace(/\.txt$/, '')
    const taskId = `CLAUDE_CODE:debug:${sessionId}`

    // Emit one task start per debug log session
    const taskStartKey = `debug_task:${path}`
    if (!this.buffer.readOffset(taskStartKey)) {
      this.buffer.writeOffset(taskStartKey, 1)
      this.buffer.offerTaskStart({
        taskId,
        sourceTool: this.sourceTool,
        title: `Claude Code Debug — ${sessionId.slice(0, 8)}`,
        startedAt: new Date().toISOString(),
        projectContext: {
          projectRoot: null,
          repoName: null,
          gitBranch: null,
          gitCommit: null,
          remoteUrl: null,
        },
      })
    }

    // Parse lines for ISO timestamps and emit events
    for (const line of text.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed) continue

      const tsMatch = trimmed.match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      this.buffer.offerItem({
        type: 'EVENT',
        taskId,
        eventType: 'LOG_LINE',
        occurredAt: tsMatch ? tsMatch[0] : new Date().toISOString(),
        payload: { line: trimmed.slice(0, 500) },
      })
    }

    const lastNl = text.lastIndexOf('\n')
    const advance = lastNl >= 0 ? lastNl + 1 : 0
    if (advance > 0) this.buffer.writeOffset(key, offset + advance)
  }

  // ─── Claude Desktop ──────────────────────────────────────────────

  /** Read plan-usage-history.json for Claude Desktop active-usage indicators. */
  private pollDesktopUsage(): void {
    const usagePath = join(
      homedir(), 'Library', 'Application Support', 'Claude', 'plan-usage-history.json',
    )
    if (!existsSync(usagePath)) return

    const key = 'desktop_usage_mtime'
    const prev = this.buffer.readOffset(key)
    try {
      const st = statSync(usagePath)
      const mtime = st.mtimeMs
      if (mtime <= prev) return
      this.buffer.writeOffset(key, mtime)

      const raw = readFileSync(usagePath, 'utf8')
      const data = JSON.parse(raw) as { version?: number; samples?: PlanUsageSample[] }
      if (!data.samples?.length) return

      // Find the most recent sample
      const latest = data.samples[data.samples.length - 1]
      const startedAt = new Date(latest.t).toISOString()
      const taskId = 'CLAUDE_DESKTOP:activity'

      this.buffer.offerTaskStart({
        taskId,
        sourceTool: this.sourceTool,
        title: 'Claude Desktop',
        startedAt,
        projectContext: {
          projectRoot: null,
          repoName: null,
          gitBranch: null,
          gitCommit: null,
          remoteUrl: null,
        },
      })

      // Emit the plan usage as a summary event
      const totalFastHours = data.samples.reduce((sum, s) => sum + (s.u?.fh ?? 0), 0)
      const totalSlowDays = data.samples.reduce((sum, s) => sum + (s.u?.sd ?? 0), 0)
      const sampleCount = data.samples.length

      this.buffer.offerItem({
        type: 'EVENT',
        taskId,
        eventType: 'SESSION_END',
        occurredAt: startedAt,
        payload: {
          totalPlanUsageSamples: sampleCount,
          totalFastHoursUsed: totalFastHours,
          totalSlowDaysUsed: totalSlowDays,
          firstSample: new Date(data.samples[0].t).toISOString(),
          lastSample: startedAt,
        },
      })
    } catch {
      // ignore
    }
  }

  // ─── Claude Desktop LevelDB (IndexedDB) — Best-effort ────────────

  /**
   * Attempt to read Claude Desktop's conversation store from LevelDB.
   * Since Chrome uses a custom `idb_cmp1` comparator and the DB is locked
   * while Claude Desktop runs, we try to copy the WAL and parse it.
   */
  private pollDesktopLevelDB(): void {
    if (this.dbCopyAttempted) return
    this.dbCopyAttempted = true

    const levelDbDir = join(
      homedir(), 'Library', 'Application Support', 'Claude',
      'IndexedDB', 'https_claude.ai_0.indexeddb.leveldb',
    )
    if (!existsSync(levelDbDir)) return

    const tmpDir = join(homedir(), '.retrysight-lite', 'claude-leveldb-tmp')
    mkdirSync(tmpDir, { recursive: true })

    // Copy current log file (WAL — most recent data, may still be locked)
    let entries: string[]
    try {
      entries = readdirSync(levelDbDir)
    } catch {
      return
    }

    const logFiles = entries.filter(f => f.endsWith('.log'))
    if (!logFiles.length) return

    // Try to copy each log file; if any is locked we skip
    let copiedAny = false
    for (const logFile of logFiles) {
      const srcPath = join(levelDbDir, logFile)
      const dstPath = join(tmpDir, logFile)
      try {
        cpSync(srcPath, dstPath, { force: true })
        copiedAny = true
      } catch {
        // Likely locked by running Claude Desktop app
      }
    }

    if (!copiedAny) {
      console.warn(
        `[retrysight-lite] Claude Desktop LevelDB is locked (Claude Desktop running) — close Claude and restart the backend for conversation data.`,
      )
      return
    }

    // Scan log files for readable JSON content
    for (const logFile of logFiles) {
      const path = join(tmpDir, logFile)
      if (!existsSync(path)) continue
      try {
        this.scanLogForConversations(path)
      } catch {
        // Continue with next file
      }
    }
  }

  private scanLogForConversations(filePath: string): void {
    const data = readFileSync(filePath)
    // Find all readable JSON-like fragments in the binary data
    const text = data.toString('utf8')

    // Look for conversation IDs in JSON fragments
    const allMatches = text.match(/".{0,30}":"/gs)
    if (!allMatches) return

    // Find UUID conversation IDs
    const foundIds = new Set<string>()
    const uuidRegex = /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/gi
    let uuidMatch
    while ((uuidMatch = uuidRegex.exec(text)) !== null) {
      const id = uuidMatch[0].toLowerCase()
      if (foundIds.has(id)) continue
      foundIds.add(id)

      const taskId = `CLAUDE_DESKTOP:${id}`
      const dedupKey = `desktop_conv_query:${id}`
      if (this.buffer.readOffset(dedupKey)) continue
      this.buffer.writeOffset(dedupKey, 1)

      this.buffer.offerTaskStart({
        taskId,
        sourceTool: this.sourceTool,
        title: 'Claude Desktop Activity',
        startedAt: new Date().toISOString(),
        projectContext: {
          projectRoot: null,
          repoName: null,
          gitBranch: null,
          gitCommit: null,
          remoteUrl: null,
        },
      })
    }
  }
}
