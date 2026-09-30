// SPDX-License-Identifier: Apache-2.0

import { existsSync, lstatSync, readdirSync, readFileSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import type { EventBuffer } from './event-buffer.js'

export type LogFormat = 'jsonl' | 'plaintext'

export interface CollectorConfig {
  filePattern: string
  format: LogFormat
}

const ISO_TIMESTAMP_RE = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})/

/**
 * Walk files matching the given pattern under `root`.
 * Pattern support: `*.ext` matches files with extension, `*` matches all files.
 */
function walkFiles(root: string, pattern: string, out: string[]): void {
  if (!existsSync(root)) return
  let st
  try {
    st = lstatSync(root)
  } catch {
    return
  }
  // Never follow symlinks: they could point outside the configured log dirs.
  if (st.isSymbolicLink()) return
  if (st.isFile()) {
    if (matchesPattern(root, pattern)) out.push(root)
    return
  }
  if (!st.isDirectory()) return
  let entries: string[]
  try {
    entries = readdirSync(root)
  } catch {
    return
  }
  for (const name of entries) {
    walkFiles(join(root, name), pattern, out)
  }
}

function matchesPattern(path: string, pattern: string): boolean {
  if (pattern === '*') return true
  // Handle simple *.ext patterns
  if (pattern.startsWith('*.')) {
    const ext = pattern.slice(1) // includes the dot: ".jsonl"
    return path.endsWith(ext)
  }
  // Handle *all* patterns
  if (pattern === '*all*') return true
  // Fallback: treat pattern as a suffix match
  return path.endsWith(pattern)
}

function asRecord(line: string): Record<string, unknown> | null {
  try {
    const v = JSON.parse(line) as unknown
    if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>
  } catch {
    /* ignore */
  }
  return null
}

function str(obj: Record<string, unknown>, key: string): string | undefined {
  const v = obj[key]
  return typeof v === 'string' ? v : undefined
}

function num(obj: Record<string, unknown>, key: string): number | undefined {
  const v = obj[key]
  return typeof v === 'number' && Number.isFinite(v) ? v : undefined
}

function asRecordOrUndefined(v: unknown): Record<string, unknown> | undefined {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined
}

/** Resolves the `{role, content}` chat message from either shape a JSONL
 *  transcript line uses: a flat top-level `{role, content}` (legacy Cursor
 *  jsonl shape, now moot since Cursor writes sqlite instead — kept for any
 *  other tool that still uses it), or nested under `message`, i.e.
 *  `{type, message: {role, content, usage, model}}` — the real Claude Code
 *  CLI transcript shape (verified against real ~/.claude/projects/*.jsonl
 *  files: the outer object's own `role` is always absent; the actual API
 *  response, role included, lives at `obj.message`). */
function resolveChatMessage(obj: Record<string, unknown>): Record<string, unknown> | undefined {
  if (typeof obj.role === 'string') return obj
  const nested = asRecordOrUndefined(obj.message)
  return nested && typeof nested.role === 'string' ? nested : undefined
}

/** `content` from a resolved chat message, normalized to an array of blocks.
 *  A user's own typed turn often stores `content` as a plain string rather
 *  than an array of blocks (verified: 14 of 215 real 'user' lines in a
 *  sampled transcript) — wrapped here as a single text block so callers
 *  don't need to special-case it. */
function chatMessageContent(obj: Record<string, unknown>): unknown[] | undefined {
  const message = resolveChatMessage(obj)
  if (!message) return undefined
  const content = message.content
  if (Array.isArray(content)) return content
  if (typeof content === 'string' && content.trim()) return [{ type: 'text', text: content }]
  return undefined
}

function firstChatText(content: unknown[]): string | undefined {
  for (const block of content) {
    if (block && typeof block === 'object' && (block as Record<string, unknown>).type === 'text') {
      const text = (block as Record<string, unknown>).text
      if (typeof text === 'string' && text.trim()) return text.trim()
    }
  }
  return undefined
}

function isToolUseBlock(c: unknown): c is Record<string, unknown> {
  return !!c && typeof c === 'object' && (c as Record<string, unknown>).type === 'tool_use'
}

function isToolResultBlock(c: unknown): c is Record<string, unknown> {
  return !!c && typeof c === 'object' && (c as Record<string, unknown>).type === 'tool_result'
}

/** Tool names that actually mutate the workspace. Everything else a real
 *  agentic tool call can do (Read, Grep, Glob, Bash, Task, WebFetch, …) is
 *  genuine agent activity but not itself a retry-worthy edit. */
const MUTATING_TOOL_NAMES = new Set(['Edit', 'MultiEdit', 'Write', 'NotebookEdit'])

/** Classifies a resolved chat message's content blocks into a concrete event
 *  type. A `tool_result` carrying `is_error: true` is the clearest signal a
 *  real agentic transcript gives us that something needed retrying — the
 *  agent's last action failed — so it wins regardless of which tool it was.
 *  Absent an error, only a mutating tool call counts as `EDIT`; every other
 *  tool call is real activity but not a retry signal, so it's `TOOL_CALL`,
 *  not `EDIT` — tagging *every* tool_use as EDIT would just reproduce the
 *  original overcounting bug one step more precisely. */
function classifyChatContent(content: unknown[]): string {
  const toolResults = content.filter(isToolResultBlock)
  if (toolResults.some((b) => b.is_error === true)) return 'TOOL_ERROR'
  const toolUses = content.filter(isToolUseBlock)
  if (toolUses.length) {
    const hasMutatingTool = toolUses.some((b) => typeof b.name === 'string' && MUTATING_TOOL_NAMES.has(b.name as string))
    return hasMutatingTool ? 'EDIT' : 'TOOL_CALL'
  }
  // A tool_result with no error is the other half of a (non-mutating or
  // mutating) tool call — neutral activity, not free-text chat.
  if (toolResults.length) return 'TOOL_CALL'
  return 'CHAT_MESSAGE'
}

export type JsonlEventClassification = {
  /** The eventType an EVENT item should carry — always set, even when
   *  `isTokenUsageLine` is true and no EVENT item ends up being emitted for
   *  this particular line (`eventType === 'TOKEN_USAGE'` in that case). */
  eventType: string
  /** The resolved usage object (top-level `obj.usage`, or the real Claude
   *  Code `obj.message.usage`), if any. */
  usage: Record<string, unknown> | undefined
  /** The resolved `message` object (`obj.message`), if any. */
  message: Record<string, unknown> | undefined
  /** Whether this line should also produce a TOKEN_USAGE item, independent
   *  of `eventType` — a real assistant turn carries both a `message.usage`
   *  and (often) a tool_use in the very same line. */
  isTokenUsageLine: boolean
}

/** Pure classification decision shared by the live collector
 * (`FlexibleLogCollector.handleJsonlLine`) and the one-off
 * `reclassify-claude-code-events` backfill script, so the two can never
 * drift out of sync. `sourceTool` only affects the final fallback (see
 * inline comment below). */
export function classifyJsonlEvent(obj: Record<string, unknown>, sourceTool: string): JsonlEventClassification {
  const chatContent = chatMessageContent(obj)
  // Real Claude Code CLI transcripts wrap the actual API response inside a
  // `message` object (`{type, message: {role, content, usage, model}}`),
  // not at the top level — verified against a real transcript file where
  // 0 of 1174 content lines had a top-level `usage`, but 365 had
  // `message.usage`. `obj.usage` is kept as the first choice so any other
  // tool that genuinely puts usage at the top level still works.
  const message = asRecordOrUndefined(obj.message)
  const usage = asRecordOrUndefined(obj.usage) ?? (message ? asRecordOrUndefined(message.usage) : undefined)

  const typeHint = (str(obj, 'type') || str(obj, 'kind') || str(obj, 'event') || '').toUpperCase()
  // Real Claude Code lines DO have a top-level `type` ('assistant'/'user'),
  // unlike the Cursor-era assumption baked into the old `!typeHint` guard
  // below — so chat-content classification must still run for those two
  // envelope values specifically (verified: neither, nor any other real
  // envelope type seen — 'system', 'attachment', 'custom-title', etc. —
  // ever collides with the TEST/COMPACT/REJECT/ACCEPT/TOKEN/START
  // substring checks above, so this can't shadow another tool's signal).
  const looksLikeChatEnvelope = !typeHint || typeHint === 'ASSISTANT' || typeHint === 'USER'
  const chatEventType = chatContent && looksLikeChatEnvelope ? classifyChatContent(chatContent) : undefined
  // A real assistant turn carries `message.usage` on the SAME line as any
  // tool_use block it makes (verified: all 365 sampled 'assistant' lines
  // had usage, 202 of those also had a tool_use) — so token accounting and
  // activity classification are two separate facts about one line, not
  // alternatives. Emit up to one item of each kind instead of picking one.
  const isTokenUsageLine = usage != null || typeHint.includes('TOKEN')

  let eventType: string
  if (typeHint.includes('TEST')) eventType = 'TEST_FAIL'
  else if (typeHint.includes('COMPACT')) eventType = 'COMPACTION'
  else if (typeHint.includes('REJECT')) eventType = 'DIFF_REJECTED'
  else if (typeHint.includes('ACCEPT')) eventType = 'DIFF_ACCEPTED'
  else if (chatEventType) eventType = chatEventType
  else if (isTokenUsageLine) eventType = 'TOKEN_USAGE'
  else if (typeHint.includes('START')) eventType = 'SESSION_START'
  else if (typeHint.includes('END')) eventType = 'SESSION_END'
  // Falling all the way through means: an explicit `type` we don't
  // recognize, and (for CLAUDE_CODE) not chat-shaped either — real Claude
  // Code transcripts carry plenty of these (bridge-session,
  // queue-operation, attachment, custom-title, atis-latch, last-prompt,
  // system, pr-link, file-history-snapshot/-delta, mode, agent-name,
  // cost-state — verified against a real transcript: 595 of 1175 lines).
  // These are session/product bookkeeping, not edits, and defaulting them
  // to 'EDIT' was the other half of the original overcounting bug. Scoped
  // to CLAUDE_CODE specifically (where the real shape is now verified) so
  // an unverified tool sharing this collector keeps its prior behavior.
  else eventType = sourceTool === 'CLAUDE_CODE' ? 'OTHER' : 'EDIT'

  return { eventType, usage, message, isTokenUsageLine }
}

function extractIsoTimestamp(line: string): string | null {
  const match = line.match(ISO_TIMESTAMP_RE)
  return match ? match[0] : null
}

function extractSessionId(path: string): string {
  // Use the parent directory name as session id for plaintext logs
  // This groups log files by their containing directory
  const dir = dirname(path)
  const dirName = basename(dir)
  let id: string
  if (dirName && dirName !== '.') {
    id = `${dirName}/${basename(path)}`
  } else {
    id = basename(path).replace(/\.[^/.]+$/, '')
  }
  // Sanitize: replace chars unsafe for URL paths with underscores
  return id.replace(/[\/\\:?#\[\]@]/g, '_')
}

function extractProjectName(path: string): string | null {
  const dir = dirname(path)
  const dirName = basename(dir)
  if (dirName && dirName !== '.') return dirName
  return null
}

/**
 * Generic flexible log collector supporting JSONL and plaintext formats,
 * with configurable file patterns and log format per tool.
 */
export class FlexibleLogCollector {
  private readonly seenTaskIds = new Set<string>()

  constructor(
    private readonly sourceTool: string,
    private readonly roots: string[],
    private readonly buffer: EventBuffer,
    private readonly config: CollectorConfig = { filePattern: '*.jsonl', format: 'jsonl' },
  ) {}

  poll(): void {
    for (const root of this.roots) {
      const files: string[] = []
      walkFiles(root, this.config.filePattern, files)
      for (const path of files) this.tailFile(path)
    }
  }

  private tailFile(path: string): void {
    const key = path
    let offset = this.buffer.readOffset(key)
    let size: number
    try {
      size = lstatSync(path).size
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

    for (const line of text.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed) continue
      this.handleLine(path, trimmed)
    }

    const lastNl = text.lastIndexOf('\n')
    const advance = lastNl >= 0 ? lastNl + 1 : 0
    if (advance > 0) this.buffer.writeOffset(key, offset + advance)
  }

  private handleLine(path: string, line: string): void {
    if (this.config.format === 'jsonl') {
      this.handleJsonlLine(path, line)
    } else {
      this.handlePlaintextLine(path, line)
    }
  }

  private handleJsonlLine(path: string, line: string): void {
    const obj = asRecord(line)
    if (!obj) return

    const sessionId =
      (str(obj, 'sessionId') ||
      str(obj, 'conversationId') ||
      str(obj, 'chatId') ||
      basename(path).replace(/.jsonl$/i, '').replace(/.log$/i, '')).replace(/[\/\\:?#\[\]@]/g, '_')
    const taskId = `${this.sourceTool}:${sessionId}`
    const chatContent = chatMessageContent(obj)
    const title =
      str(obj, 'title') ||
      str(obj, 'message') ||
      (chatContent ? firstChatText(chatContent)?.slice(0, 120) : undefined)
    const occurredAt = str(obj, 'timestamp') || str(obj, 'createdAt') || new Date().toISOString()

    // Only offer a taskStart once per session, not once per line. Every other
    // collector in this codebase (ClaudeCollector, WarpSqliteCollector, the
    // new CursorSqliteCollector) dedupes this way; this one didn't — on a
    // session file with hundreds of lines, that meant hundreds of redundant
    // taskStarts queued alongside real event items every poll. Verified this
    // wasn't just wasteful: `EventBuffer.drain()` fully drains all queued
    // taskStarts before ever touching items, so once taskStart volume roughly
    // matched item volume (1:1, one of each per line), items were starved
    // completely — no event ever reached task_events, no retry_count ever
    // moved, for as long as the taskStart backlog stayed above the per-flush
    // cap.
    if (!this.seenTaskIds.has(taskId)) {
      this.seenTaskIds.add(taskId)
      this.buffer.offerTaskStart({
        taskId,
        sourceTool: this.sourceTool,
        title: title ?? null,
        startedAt: occurredAt,
        projectContext: {
          projectRoot: str(obj, 'cwd') || str(obj, 'workspace') || null,
          repoName: str(obj, 'repo') || basename(dirname(path)) || null,
          gitBranch: null,
          gitCommit: null,
          remoteUrl: null,
        },
      })
    }

    const { eventType, usage, message, isTokenUsageLine } = classifyJsonlEvent(obj, this.sourceTool)

    if (isTokenUsageLine) {
      this.buffer.offerItem({
        type: 'TOKEN_USAGE',
        taskId,
        model: str(obj, 'model') || (message && str(message, 'model')) || (usage ? str(usage, 'model') : undefined) || null,
        inputTokens:
          (usage ? num(usage, 'input_tokens') ?? num(usage, 'inputTokens') : undefined) ??
          num(obj, 'inputTokens') ??
          null,
        outputTokens:
          (usage ? num(usage, 'output_tokens') ?? num(usage, 'outputTokens') : undefined) ??
          num(obj, 'outputTokens') ??
          null,
        occurredAt,
      })
    }
    if (eventType !== 'TOKEN_USAGE') {
      this.buffer.offerItem({
        type: 'EVENT',
        taskId,
        eventType,
        occurredAt,
        payload: obj,
      })
    }
  }

  private handlePlaintextLine(path: string, line: string): void {
    const sessionId = extractSessionId(path)
    const taskId = `${this.sourceTool}:${sessionId}`
    const occurredAt = extractIsoTimestamp(line) || new Date().toISOString()
    const projectName = extractProjectName(path)

    // For plaintext logs, we emit a task start per session on first encounter
    // and EVENT items for each log line
    this.buffer.offerTaskStart({
      taskId,
      sourceTool: this.sourceTool,
      title: basename(path),
      startedAt: occurredAt,
      projectContext: {
        projectRoot: null,
        repoName: projectName,
        gitBranch: null,
        gitCommit: null,
        remoteUrl: null,
      },
    })

    this.buffer.offerItem({
      type: 'EVENT',
      taskId,
      eventType: 'LOG_LINE',
      occurredAt,
      payload: { line, path: basename(path) },
    })
  }
}
