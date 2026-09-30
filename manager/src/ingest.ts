// SPDX-License-Identifier: Apache-2.0

import { z } from 'zod'
import {
  AgentRow,
  cryptoRandomId,
  getDb,
  nowIso,
  TaskRow,
  verifyApiKey,
} from './db.js'

const MAX_ARRAY = 100
const MAX_STR = 2048
const MAX_PAYLOAD_JSON = 32_768

/** Strip HTML tags, javascript: URIs, and on-event attributes from a string.
 *  This is a best-effort defense-in-depth measure — it is NOT a defense against
 *  prompt injection. Ingested text (task titles, branch names, event notes, …)
 *  is later surfaced verbatim to LLM agents via the MCP tools in mcp-stdio.ts,
 *  so it must always be treated as untrusted data by consumers of that API,
 *  regardless of this sanitization. */
function sanitizeString(value: string): string {
  return value
    .replace(/<[^>]*>/g, '')
    .replace(/javascript\s*:/gi, 'blocked:')
    .replace(/on\w+\s*=/gi, 'blocked=')
}

/** Sanitize a scalar free-text field (title, branch name, etc.). Passes through non-strings unchanged. */
function sanitizeText<T extends string | null | undefined>(value: T): T {
  return (typeof value === 'string' ? sanitizeString(value) : value) as T
}

function sanitizePayload(payload: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(payload)) {
    if (typeof value === 'string') {
      result[key] = sanitizeString(value)
    } else if (value !== null && typeof value === 'object') {
      result[key] = sanitizePayload(value as Record<string, unknown>)
    } else {
      result[key] = value
    }
  }
  return result
}

const limitedString = (max = MAX_STR) => z.string().max(max)
/** Loose email-shape check (accepts the app's own `user@local` self-heartbeat
 *  identities, which have no TLD and would fail zod's strict `.email()`) while
 *  still rejecting empty/whitespace/multi-@ garbage. */
const emailLike = (max = 320) =>
  z.string().max(max).regex(/^[^\s@]+@[^\s@]+$/, 'Invalid email address')

const projectContextSchema = z
  .object({
    projectRoot: limitedString().optional().nullable(),
    repoName: limitedString(512).optional().nullable(),
    gitBranch: limitedString(512).optional().nullable(),
    gitCommit: limitedString(128).optional().nullable(),
    remoteUrl: limitedString().optional().nullable(),
  })
  .optional()
  .nullable()

export const heartbeatSchema = z.object({
  name: limitedString(256).min(1),
  developerEmail: emailLike(320),
  hostname: limitedString(256).min(1),
  osUsername: limitedString(256).optional().nullable(),
  displayName: limitedString(256).optional().nullable(),
  gitEmail: limitedString(320).optional().nullable(),
  installedCollectors: z.array(limitedString(64)).max(32).optional().nullable(),
})

const taskStartSchema = z.object({
  taskId: limitedString(512).min(1),
  sourceTool: limitedString(64).min(1),
  title: limitedString().optional().nullable(),
  startedAt: limitedString(64).optional().nullable(),
  projectContext: projectContextSchema,
})

const eventItemSchema = z.object({
  type: z.literal('EVENT'),
  taskId: limitedString(512).min(1),
  eventType: limitedString(64).min(1),
  occurredAt: limitedString(64).optional().nullable(),
  payload: z.record(z.unknown()).optional().nullable(),
})

const tokenItemSchema = z.object({
  type: z.literal('TOKEN_USAGE'),
  taskId: limitedString(512).min(1),
  model: limitedString(256).optional().nullable(),
  inputTokens: z.number().int().nonnegative().optional().nullable(),
  outputTokens: z.number().int().nonnegative().optional().nullable(),
  occurredAt: limitedString(64).optional().nullable(),
})

const completeItemSchema = z.object({
  type: z.literal('TASK_COMPLETE'),
  taskId: limitedString(512).min(1),
  status: z.enum(['COMPLETED', 'ABANDONED']).optional().nullable(),
  endedAt: limitedString(64).optional().nullable(),
})

const batchItemSchema = z.discriminatedUnion('type', [
  eventItemSchema,
  tokenItemSchema,
  completeItemSchema,
])

export const batchRequestSchema = z.object({
  heartbeat: heartbeatSchema.optional().nullable(),
  taskStarts: z.array(taskStartSchema).max(MAX_ARRAY).optional().nullable(),
  items: z.array(batchItemSchema).max(MAX_ARRAY).optional().nullable(),
})

export type HeartbeatRequest = z.infer<typeof heartbeatSchema>
export type BatchRequest = z.infer<typeof batchRequestSchema>

export function assertAgentKey(apiKey: string | undefined): string {
  if (!apiKey) {
    console.error(`[retrysight-lite] Failed agent key auth — missing key`)
    const err = new Error('Invalid agent API key')
    ;(err as Error & { statusCode: number }).statusCode = 401
    throw err
  }
  const keyHash = verifyApiKey(apiKey)
  if (!keyHash) {
    console.error(`[retrysight-lite] Failed agent key auth — invalid key prefix=${apiKey.slice(0, 8)}`)
    const err = new Error('Invalid agent API key')
    ;(err as Error & { statusCode: number }).statusCode = 401
    throw err
  }
  return keyHash
}

function assertTaskOwnedByAgent(taskId: string, agentId: string): void {
  const existing = getDb()
    .prepare('SELECT agent_id FROM tasks WHERE id = ?')
    .get(taskId) as { agent_id: string } | undefined
  if (existing && existing.agent_id !== agentId) {
    const err = new Error(`Task ${taskId} belongs to another agent`)
    ;(err as Error & { statusCode: number }).statusCode = 403
    throw err
  }
}

export function registerOrResolveAgent(
  agentId: string | undefined,
  heartbeat: HeartbeatRequest | null | undefined,
  registeredByKeyHash?: string | null,
): AgentRow {
  const db = getDb()
  const ts = nowIso()

  if (agentId) {
    const existing = db.prepare('SELECT * FROM agents WHERE id = ?').get(agentId) as
      | AgentRow
      | undefined
    if (existing) {
      // Prevent agent-ID spoofing: if the agent was registered by a specific key,
      // the current request must use the same key.
      if (existing.registered_by_key_hash) {
        if (registeredByKeyHash && registeredByKeyHash !== existing.registered_by_key_hash) {
          const err = new Error('Agent belongs to a different API key')
          ;(err as Error & { statusCode: number }).statusCode = 403
          throw err
        }
      } else if (registeredByKeyHash) {
        // Legacy/pre-migration agent with no key on record: the first caller to
        // present a key from here on claims and locks the agent to that key,
        // closing the window where any valid agent key could adopt it.
        db.prepare('UPDATE agents SET registered_by_key_hash = ? WHERE id = ?').run(
          registeredByKeyHash,
          agentId,
        )
        existing.registered_by_key_hash = registeredByKeyHash
      }
      if (heartbeat) {
        db.prepare(
          `UPDATE agents SET
            name = ?, developer_email = ?, hostname = ?,
            os_username = ?, display_name = ?, git_email = ?,
            installed_collectors = ?, last_heartbeat_at = ?
           WHERE id = ?`,
        ).run(
          sanitizeText(heartbeat.name),
          heartbeat.developerEmail,
          sanitizeText(heartbeat.hostname),
          sanitizeText(heartbeat.osUsername) ?? null,
          sanitizeText(heartbeat.displayName) ?? null,
          sanitizeText(heartbeat.gitEmail) ?? null,
          heartbeat.installedCollectors?.join(',') ?? existing.installed_collectors,
          ts,
          agentId,
        )
      } else {
        db.prepare('UPDATE agents SET last_heartbeat_at = ? WHERE id = ?').run(ts, agentId)
      }
      return db.prepare('SELECT * FROM agents WHERE id = ?').get(agentId) as AgentRow
    }
  }

  if (!heartbeat) {
    const err = new Error('Either X-Agent-Id or heartbeat payload is required')
    ;(err as Error & { statusCode: number }).statusCode = 400
    throw err
  }

  const id = agentId || cryptoRandomId()
  db.prepare(
    `INSERT INTO agents (
      id, name, developer_email, os_username, display_name, git_email,
      hostname, last_heartbeat_at, installed_collectors, registered_by_key_hash, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    sanitizeText(heartbeat.name),
    heartbeat.developerEmail,
    sanitizeText(heartbeat.osUsername) ?? null,
    sanitizeText(heartbeat.displayName) ?? null,
    sanitizeText(heartbeat.gitEmail) ?? null,
    sanitizeText(heartbeat.hostname),
    ts,
    heartbeat.installedCollectors?.join(',') ?? null,
    registeredByKeyHash ?? null,
    ts,
  )
  return db.prepare('SELECT * FROM agents WHERE id = ?').get(id) as AgentRow
}

export function processBatch(agentId: string, body: BatchRequest) {
  const db = getDb()
  const ts = nowIso()
  let tasksCreated = 0
  let eventsAccepted = 0
  let tokensAccepted = 0

  const upsertTask = db.prepare(
    `INSERT INTO tasks (
      id, agent_id, source_tool, status, title, retry_count,
      input_tokens, output_tokens, started_at, ended_at,
      project_root, repo_name, git_branch, git_commit, remote_url,
      created_at, updated_at
    ) VALUES (?, ?, ?, 'ACTIVE', ?, 0, 0, 0, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = COALESCE(excluded.title, tasks.title),
      project_root = COALESCE(excluded.project_root, tasks.project_root),
      repo_name = COALESCE(excluded.repo_name, tasks.repo_name),
      git_branch = COALESCE(excluded.git_branch, tasks.git_branch),
      git_commit = COALESCE(excluded.git_commit, tasks.git_commit),
      remote_url = COALESCE(excluded.remote_url, tasks.remote_url),
      updated_at = excluded.updated_at
    WHERE tasks.agent_id = excluded.agent_id`,
  )

  for (const start of body.taskStarts ?? []) {
    assertTaskOwnedByAgent(start.taskId, agentId)
    const before = db.prepare('SELECT id FROM tasks WHERE id = ?').get(start.taskId)
    upsertTask.run(
      start.taskId,
      agentId,
      start.sourceTool,
      sanitizeText(start.title) ?? null,
      start.startedAt ?? ts,
      sanitizeText(start.projectContext?.projectRoot) ?? null,
      sanitizeText(start.projectContext?.repoName) ?? null,
      sanitizeText(start.projectContext?.gitBranch) ?? null,
      sanitizeText(start.projectContext?.gitCommit) ?? null,
      sanitizeText(start.projectContext?.remoteUrl) ?? null,
      ts,
      ts,
    )
    if (!before) tasksCreated += 1
  }

  const insertEvent = db.prepare(
    `INSERT INTO task_events (id, task_id, event_type, payload_json, occurred_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
  const bumpRetry = db.prepare(
    `UPDATE tasks SET retry_count = retry_count + 1, updated_at = ? WHERE id = ? AND agent_id = ?`,
  )
  const bumpTokens = db.prepare(
    `UPDATE tasks SET
      input_tokens = input_tokens + ?,
      output_tokens = output_tokens + ?,
      updated_at = ?
     WHERE id = ? AND agent_id = ?`,
  )
  const completeTask = db.prepare(
    `UPDATE tasks SET status = ?, ended_at = ?, updated_at = ? WHERE id = ? AND agent_id = ?`,
  )
  const ensureTask = db.prepare(
    `INSERT OR IGNORE INTO tasks (
      id, agent_id, source_tool, status, title, retry_count,
      input_tokens, output_tokens, started_at, ended_at,
      project_root, repo_name, git_branch, git_commit, remote_url,
      created_at, updated_at
    ) VALUES (?, ?, 'UNKNOWN', 'ACTIVE', NULL, 0, 0, 0, ?, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?)`,
  )

  for (const item of body.items ?? []) {
    assertTaskOwnedByAgent(item.taskId, agentId)
    ensureTask.run(item.taskId, agentId, ts, ts, ts)
    // Re-check: INSERT OR IGNORE won't overwrite another agent's task
    assertTaskOwnedByAgent(item.taskId, agentId)

    if (item.type === 'EVENT') {
      let payloadJson: string | null = null
      if (item.payload) {
        const sanitized = sanitizePayload(item.payload)
        const raw = JSON.stringify(sanitized)
        payloadJson = raw.length > MAX_PAYLOAD_JSON ? raw.slice(0, MAX_PAYLOAD_JSON) : raw
      }
      insertEvent.run(
        cryptoRandomId(),
        item.taskId,
        item.eventType,
        payloadJson,
        item.occurredAt ?? ts,
        ts,
      )
      eventsAccepted += 1
      if (['EDIT', 'TEST_FAIL', 'DIFF_REJECTED', 'COMPACTION', 'COMMAND_FAILED', 'TOOL_ERROR'].includes(item.eventType)) {
        bumpRetry.run(ts, item.taskId, agentId)
      }
    } else if (item.type === 'TOKEN_USAGE') {
      const input = item.inputTokens ?? 0
      const output = item.outputTokens ?? 0
      bumpTokens.run(input, output, ts, item.taskId, agentId)
      insertEvent.run(
        cryptoRandomId(),
        item.taskId,
        'TOKEN_USAGE',
        JSON.stringify({
          model: item.model ?? null,
          inputTokens: input,
          outputTokens: output,
        }),
        item.occurredAt ?? ts,
        ts,
      )
      tokensAccepted += 1
    } else if (item.type === 'TASK_COMPLETE') {
      completeTask.run(item.status ?? 'COMPLETED', item.endedAt ?? ts, ts, item.taskId, agentId)
    }
  }

  return { tasksCreated, eventsAccepted, tokensAccepted }
}

/** Mark ACTIVE tasks as COMPLETED if they haven't seen any updates within the stale window.
 *  Returns the number of tasks completed.
 */
export function completeStaleTasks(maxStaleMinutes = 5): number {
  const db = getDb()
  const now = new Date().toISOString()
  const cutoff = new Date(Date.now() - maxStaleMinutes * 60_000).toISOString()
  const result = db.prepare(
    `UPDATE tasks SET status = 'COMPLETED', ended_at = ?, updated_at = ?
     WHERE status = 'ACTIVE' AND updated_at < ?`,
  ).run(now, now, cutoff)
  const count = Number(result.changes)
  if (count > 0) {
    console.log(`[retrysight-lite] Auto-completed ${count} stale tasks (no activity for >${maxStaleMinutes}m)`)
  }
  return count
}

export function listAgents(): AgentRow[] {
  return getDb().prepare('SELECT * FROM agents ORDER BY created_at DESC').all() as AgentRow[]
}

export function getAgent(id: string): AgentRow | undefined {
  return getDb().prepare('SELECT * FROM agents WHERE id = ?').get(id) as AgentRow | undefined
}

export type TaskFilters = {
  agentId?: string
  sourceTool?: string
  from?: string
  to?: string
  minRetries?: number
  page?: number
  size?: number
}

function buildTaskFilterClause(filters: TaskFilters): { where: string; params: Array<string | number> } {
  const clauses: string[] = []
  const params: Array<string | number> = []
  if (filters.agentId) {
    clauses.push('agent_id = ?')
    params.push(filters.agentId)
  }
  if (filters.sourceTool) {
    clauses.push('source_tool = ?')
    params.push(filters.sourceTool)
  }
  if (filters.from) {
    clauses.push('started_at >= ?')
    params.push(filters.from)
  }
  if (filters.to) {
    clauses.push('started_at <= ?')
    params.push(filters.to)
  }
  if (filters.minRetries != null) {
    clauses.push('retry_count >= ?')
    params.push(filters.minRetries)
  }
  return { where: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '', params }
}

/** Bound export size so a very large local DB can't produce an unbounded
 *  response — this is a local, admin-only export, not a paginated API, but
 *  still shouldn't be able to try to serialize millions of rows in one go. */
const MAX_EXPORT_ROWS = 50_000

export function listTasksForExport(filters: TaskFilters): TaskRow[] {
  const { where, params } = buildTaskFilterClause(filters)
  return getDb()
    .prepare(`SELECT * FROM tasks ${where} ORDER BY started_at DESC LIMIT ?`)
    .all(...params, MAX_EXPORT_ROWS) as TaskRow[]
}

export function listTasks(filters: TaskFilters): { items: TaskRow[]; totalCount: number } {
  const { where, params } = buildTaskFilterClause(filters)
  const totalCount = (
    getDb().prepare(`SELECT COUNT(*) AS c FROM tasks ${where}`).get(...params) as { c: number }
  ).c
  const size = Math.min(Math.max(filters.size ?? 50, 1), 200)
  const page = Math.max(filters.page ?? 0, 0)
  const items = getDb()
    .prepare(
      `SELECT * FROM tasks ${where} ORDER BY started_at DESC LIMIT ? OFFSET ?`,
    )
    .all(...params, size, page * size) as TaskRow[]
  return { items, totalCount }
}

export function getTask(id: string): TaskRow | undefined {
  return getDb().prepare('SELECT * FROM tasks WHERE id = ?').get(id) as TaskRow | undefined
}

export function listEvents(taskId: string) {
  return getDb()
    .prepare('SELECT * FROM task_events WHERE task_id = ? ORDER BY occurred_at ASC')
    .all(taskId)
}
