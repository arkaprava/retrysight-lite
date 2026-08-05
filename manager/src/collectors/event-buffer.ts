// SPDX-License-Identifier: Apache-2.0

import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs'
import { join } from 'node:path'
import type { BatchRequest } from '../ingest.js'

export type TaskStart = NonNullable<NonNullable<BatchRequest['taskStarts']>[number]>
export type BatchItem = NonNullable<NonNullable<BatchRequest['items']>[number]>

/**
 * In-memory buffer with flat-file offsets under the collector data dir.
 */
export class EventBuffer {
  private readonly taskStarts: TaskStart[] = []
  private readonly items: BatchItem[] = []
  private readonly offsetsFile: string
  private readonly bufferFile: string

  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 })
    try { chmodSync(dataDir, 0o700) } catch { /* best effort */ }
    this.offsetsFile = join(dataDir, 'offsets.json')
    this.bufferFile = join(dataDir, 'buffer.jsonl')
    if (!existsSync(this.offsetsFile)) writeFileSync(this.offsetsFile, '{}', { encoding: 'utf8', mode: 0o600 })
    if (!existsSync(this.bufferFile)) writeFileSync(this.bufferFile, '', { encoding: 'utf8', mode: 0o600 })
  }

  offerTaskStart(start: TaskStart): void {
    this.taskStarts.push(start)
    appendFileSync(this.bufferFile, `${JSON.stringify({ kind: 'taskStart', payload: start })}\n`)
  }

  offerItem(item: BatchItem): void {
    this.items.push(item)
    appendFileSync(this.bufferFile, `${JSON.stringify({ kind: 'item', payload: item })}\n`)
  }

  drain(max = 200): { taskStarts: TaskStart[]; items: BatchItem[] } {
    const taskStarts: TaskStart[] = []
    const items: BatchItem[] = []
    while (taskStarts.length + items.length < max) {
      if (this.taskStarts.length) {
        taskStarts.push(this.taskStarts.shift()!)
        continue
      }
      if (!this.items.length) break
      items.push(this.items.shift()!)
    }
    return { taskStarts, items }
  }

  readOffset(key: string): number {
    try {
      const map = JSON.parse(readFileSync(this.offsetsFile, 'utf8')) as Record<string, number>
      return map[key] ?? 0
    } catch {
      return 0
    }
  }

  writeOffset(key: string, value: number): void {
    let map: Record<string, number> = {}
    try {
      map = JSON.parse(readFileSync(this.offsetsFile, 'utf8')) as Record<string, number>
    } catch {
      map = {}
    }
    map[key] = value
    writeFileSync(this.offsetsFile, JSON.stringify(map), { encoding: 'utf8', mode: 0o600 })
  }
}
