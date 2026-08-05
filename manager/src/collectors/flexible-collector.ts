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
 * Generic flexible log collector supporting JSONL and plaintext formats.
 * Replaces JsonlTailCollector with configurable file patterns and log format.
 */
export class FlexibleLogCollector {
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
    const title = str(obj, 'title') || str(obj, 'message')?.slice(0, 80)
    const occurredAt = str(obj, 'timestamp') || str(obj, 'createdAt') || new Date().toISOString()

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

    const typeHint = (str(obj, 'type') || str(obj, 'kind') || str(obj, 'event') || 'EDIT').toUpperCase()
    let eventType = 'EDIT'
    if (typeHint.includes('TEST')) eventType = 'TEST_FAIL'
    else if (typeHint.includes('COMPACT')) eventType = 'COMPACTION'
    else if (typeHint.includes('REJECT')) eventType = 'DIFF_REJECTED'
    else if (typeHint.includes('ACCEPT')) eventType = 'DIFF_ACCEPTED'
    else if (typeHint.includes('TOKEN') || obj.usage) eventType = 'TOKEN_USAGE'
    else if (typeHint.includes('START')) eventType = 'SESSION_START'
    else if (typeHint.includes('END')) eventType = 'SESSION_END'

    const usage =
      obj.usage && typeof obj.usage === 'object' && !Array.isArray(obj.usage)
        ? (obj.usage as Record<string, unknown>)
        : null

    if (eventType === 'TOKEN_USAGE' || usage) {
      this.buffer.offerItem({
        type: 'TOKEN_USAGE',
        taskId,
        model: str(obj, 'model') || (usage ? str(usage, 'model') : undefined) || null,
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
    } else {
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
