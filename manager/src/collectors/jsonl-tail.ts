// SPDX-License-Identifier: Apache-2.0

import { existsSync, lstatSync, readdirSync, readFileSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'
import type { EventBuffer } from './event-buffer.js'

function walkJsonl(root: string, out: string[]): void {
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
    if (root.endsWith('.jsonl')) out.push(root)
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
    walkJsonl(join(root, name), out)
  }
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

/**
 * Generic JSONL session tailer for Cursor / Claude-style logs.
 */
export class JsonlTailCollector {
  constructor(
    private readonly sourceTool: string,
    private readonly roots: string[],
    private readonly buffer: EventBuffer,
  ) {}

  poll(): void {
    for (const root of this.roots) {
      const files: string[] = []
      walkJsonl(root, files)
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
    const obj = asRecord(line)
    if (!obj) return

    const sessionId =
      str(obj, 'sessionId') ||
      str(obj, 'conversationId') ||
      str(obj, 'chatId') ||
      basename(path).replace(/\.jsonl$/i, '')
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
}
