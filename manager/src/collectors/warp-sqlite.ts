// SPDX-License-Identifier: Apache-2.0

import { DatabaseSync } from 'node:sqlite'
import { existsSync } from 'node:fs'
import type { EventBuffer } from './event-buffer.js'

interface WarpConversationRow {
  id: number
  conversation_id: string
  conversation_data: string
  last_modified_at: string
  summary: string | null
}

interface WarpTaskRow {
  id: number
  conversation_id: string
  task_id: string
  task: Buffer
  last_modified_at: string
}

interface WarpBlockRow {
  id: number
  ai_metadata: string
  start_ts: string | null
  completed_ts: string | null
  pwd: string | null
  git_branch: string | null
  exit_code: number
  user: string | null
  host: string | null
}

interface TokenUsageEntry {
  model_id: string
  warp_tokens?: number
  byok_tokens?: number
  custom_endpoint_tokens?: number
}

interface UsageMetadata {
  was_summarized?: boolean
  context_window_usage?: number
  credits_spent?: number
  credits_spent_for_last_block?: number
  token_usage?: TokenUsageEntry[]
  tool_usage_metadata?: {
    run_command_stats?: { count: number; commands_executed?: number }
    read_files_stats?: { count: number }
    search_codebase_stats?: { count: number }
    grep_stats?: { count: number }
    file_glob_stats?: { count: number }
  }
}

interface ConversationData {
  server_conversation_token?: string
  conversation_usage_metadata?: UsageMetadata
}

const OFFSET_NS = 'WARP_SQLITE'

/**
 * Reads Warp/Oz agent data directly from Warp's SQLite database.
 * Opens the DB read-only so it works alongside a running Warp app.
 */
export class WarpSqliteCollector {
  private db: DatabaseSync | null = null
  private readonly stmtConversations: ReturnType<DatabaseSync['prepare']> | null = null
  private readonly stmtTasks: ReturnType<DatabaseSync['prepare']> | null = null
  private readonly stmtBlocks: ReturnType<DatabaseSync['prepare']> | null = null

  constructor(
    private readonly sourceTool: string,
    private readonly warpDbPath: string,
    private readonly buffer: EventBuffer,
    private readonly roots: string[],
  ) {
    if (!existsSync(warpDbPath)) {
      console.warn(`[retrysight-lite] Warp SQLite DB not found at ${warpDbPath}`)
      return
    }
    try {
      this.db = new DatabaseSync(warpDbPath, { readOnly: true }) as unknown as DatabaseSync
      // WAL mode allows concurrent readers alongside the running Warp app
      this.db.exec('PRAGMA query_only = ON')
      this.db.exec('PRAGMA journal_mode = WAL')
      console.log(`[retrysight-lite] Warp SQLite collector opened ${warpDbPath}`)
    } catch (err) {
      console.error(`[retrysight-lite] Warp SQLite collector: cannot open ${warpDbPath}: ${err}`)
    }
  }

  poll(): void {
    if (!this.db) return
    this.pollConversations()
    this.pollTasks()
    this.pollBlocks()
  }

  private lastOffset(key: string): number {
    return this.buffer.readOffset(`${OFFSET_NS}:${key}`)
  }

  private saveOffset(key: string, value: number): void {
    this.buffer.writeOffset(`${OFFSET_NS}:${key}`, value)
  }

  /** Extract task title from conversation_data or summary. */
  private extractTitle(data: ConversationData, summary: string | null): string | null {
    if (summary?.trim()) return summary.trim().slice(0, 120)
    return null
  }

  /** Emit a task-start record from a Warp conversation. */
  private handleConversation(row: WarpConversationRow): void {
    let data: ConversationData
    try {
      data = JSON.parse(row.conversation_data) as ConversationData
    } catch {
      data = {}
    }
    const usage = data.conversation_usage_metadata
    const taskId = `WARP:${row.conversation_id}`
    const title = this.extractTitle(data, row.summary)
    const startedAt = row.last_modified_at || new Date().toISOString()
    this.buffer.offerTaskStart({
      taskId,
      sourceTool: this.sourceTool,
      title,
      startedAt,
      projectContext: {
        projectRoot: null,
        repoName: null,
        gitBranch: null,
        gitCommit: null,
        remoteUrl: null,
      },
    })

    // Emit token usage for each model
    if (usage?.token_usage) {
      for (const tu of usage.token_usage) {
        // Warp stores token data in different fields depending on endpoint type:
        //   - warp_tokens: Warp-hosted models (Claude, GPT, etc.)
        //   - custom_endpoint_tokens: custom endpoints (DeepSeek, etc.)
        //   - byok_tokens: bring-your-own-key
        // Sum all fields to get the total, then estimate a 40/60 input/output split
        const totalTokens = (tu.warp_tokens ?? 0) + (tu.byok_tokens ?? 0) + (tu.custom_endpoint_tokens ?? 0)
        const estimatedInput = Math.ceil(totalTokens * 0.4)
        const estimatedOutput = totalTokens - estimatedInput
        this.buffer.offerItem({
          type: 'TOKEN_USAGE',
          taskId,
          model: tu.model_id || null,
          inputTokens: estimatedInput,
          outputTokens: estimatedOutput,
          occurredAt: startedAt,
        })
      }
    }

    // Emit tool usage stats as an event
    if (usage?.tool_usage_metadata) {
      const tools = usage.tool_usage_metadata
      this.buffer.offerItem({
        type: 'EVENT',
        taskId,
        eventType: 'TOOL_USAGE',
        occurredAt: startedAt,
        payload: {
          creditsSpent: usage.credits_spent,
          contextWindowUsage: usage.context_window_usage,
          wasSummarized: usage.was_summarized,
          runCommands: tools.run_command_stats?.count ?? 0,
          readFiles: tools.read_files_stats?.count ?? 0,
          searchCodebase: tools.search_codebase_stats?.count ?? 0,
          grep: tools.grep_stats?.count ?? 0,
          fileGlob: tools.file_glob_stats?.count ?? 0,
        } as Record<string, unknown>,
      })
    }

    // Emit SESSION_START event
    this.buffer.offerItem({
      type: 'EVENT',
      taskId,
      eventType: 'SESSION_START',
      occurredAt: startedAt,
      payload: {
        summary: row.summary,
        tokenUsage: usage?.token_usage,
        toolsUsed: usage?.tool_usage_metadata ? Object.keys(usage.tool_usage_metadata).filter(k => (usage!.tool_usage_metadata as Record<string, { count: number }>)[k]?.count > 0) : [],
      } as Record<string, unknown>,
    })
  }

  /** Emit task events from Warp agent_tasks records. */
  private handleTask(row: WarpTaskRow): void {
    const taskId = `WARP:${row.conversation_id}`
    const occurredAt = row.last_modified_at || new Date().toISOString()

    // Try to parse the task blob as JSON
    let payload: Record<string, unknown>
    try {
      payload = JSON.parse(row.task.toString('utf8')) as Record<string, unknown>
    } catch {
      payload = { rawLength: row.task.length }
    }

    this.buffer.offerItem({
      type: 'EVENT',
      taskId,
      eventType: 'SUBAGENT',
      occurredAt,
      payload,
    })
  }

  /** Emit block events from Warp blocks that have ai_metadata. */
  private handleBlock(row: WarpBlockRow): void {
    let meta: Record<string, unknown>
    try {
      meta = JSON.parse(row.ai_metadata) as Record<string, unknown>
    } catch {
      meta = {}
    }
    const convId = (meta.conversation_id as string) || 'unknown'
    const taskId = `WARP:${convId}`
    const occurredAt = row.start_ts || row.completed_ts || new Date().toISOString()
    const subagentTaskId = meta.subagent_task_id as string | null

    const eventType = subagentTaskId ? 'SUBAGENT' : 'EDIT'
    this.buffer.offerItem({
      type: 'EVENT',
      taskId,
      eventType,
      occurredAt,
      payload: {
        blockId: row.id,
        pwd: row.pwd,
        gitBranch: row.git_branch,
        exitCode: row.exit_code,
        user: row.user,
        host: row.host,
        startTs: row.start_ts,
        completedTs: row.completed_ts,
        subagentTaskId,
        hasAgentWritten: meta.has_agent_written_to_block,
        longRunning: meta.long_running_control_state ? true : false,
      } as Record<string, unknown>,
    })
  }

  private pollConversations(): void {
    const lastId = this.lastOffset('conversations_last_id')
    let maxId = lastId
    try {
      const stmt = this.db!.prepare(
        'SELECT id, conversation_id, conversation_data, last_modified_at, summary FROM agent_conversations WHERE id > ? ORDER BY id',
      )
      const rows = stmt.all(lastId) as unknown as WarpConversationRow[]
      for (const row of rows) {
        this.handleConversation(row)
        if (row.id > maxId) maxId = row.id
      }
    } catch (err) {
      console.error(`[retrysight-lite] Warp SQLite: conversation poll error: ${err}`)
    }
    if (maxId > lastId) this.saveOffset('conversations_last_id', maxId)
  }

  private pollTasks(): void {
    const lastId = this.lastOffset('tasks_last_id')
    let maxId = lastId
    try {
      const stmt = this.db!.prepare(
        'SELECT id, conversation_id, task_id, task, last_modified_at FROM agent_tasks WHERE id > ? ORDER BY id',
      )
      const rows = stmt.all(lastId) as unknown as WarpTaskRow[]
      for (const row of rows) {
        this.handleTask(row)
        if (row.id > maxId) maxId = row.id
      }
    } catch (err) {
      console.error(`[retrysight-lite] Warp SQLite: task poll error: ${err}`)
    }
    if (maxId > lastId) this.saveOffset('tasks_last_id', maxId)
  }

  private pollBlocks(): void {
    const lastId = this.lastOffset('blocks_last_id')
    let maxId = lastId
    try {
      const stmt = this.db!.prepare(
        `SELECT id, ai_metadata, start_ts, completed_ts, pwd, git_branch, exit_code, user, host
         FROM blocks WHERE id > ? AND ai_metadata IS NOT NULL ORDER BY id`,
      )
      const rows = stmt.all(lastId) as unknown as WarpBlockRow[]
      for (const row of rows) {
        this.handleBlock(row)
        if (row.id > maxId) maxId = row.id
      }
    } catch (err) {
      console.error(`[retrysight-lite] Warp SQLite: block poll error: ${err}`)
    }
    if (maxId > lastId) this.saveOffset('blocks_last_id', maxId)
  }
}
