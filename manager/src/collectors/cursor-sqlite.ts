// SPDX-License-Identifier: Apache-2.0

import { DatabaseSync } from 'node:sqlite'
import { existsSync } from 'node:fs'
import { basename } from 'node:path'
import type { EventBuffer } from './event-buffer.js'

interface AiCodeHashRow {
  rowid: number
  source: string
  fileExtension: string | null
  fileName: string | null
  requestId: string | null
  conversationId: string | null
  model: string | null
  createdAt: number
}

const OFFSET_NS = 'CURSOR_SQLITE'

/**
 * Reads Cursor's local AI-code-attribution database (~/.cursor/ai-tracking/ai-code-tracking.db).
 *
 * Cursor no longer writes the `.jsonl` chat transcripts the generic
 * FlexibleLogCollector expects for this tool — verified against a real
 * local Cursor install: zero `.jsonl` files exist anywhere under its
 * configured roots. Modern Cursor instead tracks AI-authored edits in this
 * SQLite database (each row = one AI-authored code hash, grouped by
 * conversationId). Opens read-only so it works alongside a running Cursor
 * instance; the DB is not in WAL mode on a stock install, so occasional
 * "database is locked" errors during a concurrent write are expected and
 * simply retried on the next poll.
 */
export class CursorSqliteCollector {
  private db: DatabaseSync | null = null
  private readonly seenConversations = new Set<string>()

  constructor(
    private readonly sourceTool: string,
    private readonly dbPath: string,
    private readonly buffer: EventBuffer,
  ) {
    if (!existsSync(dbPath)) {
      console.warn(`[retrysight-lite] Cursor AI-tracking DB not found at ${dbPath}`)
      return
    }
    try {
      this.db = new DatabaseSync(dbPath, { readOnly: true }) as unknown as DatabaseSync
      this.db.exec('PRAGMA query_only = ON')
      console.log(`[retrysight-lite] Cursor SQLite collector opened ${dbPath}`)
    } catch (err) {
      console.error(`[retrysight-lite] Cursor SQLite collector: cannot open ${dbPath}: ${err}`)
    }
  }

  poll(): void {
    if (!this.db) return
    this.pollHashes()
  }

  private lastOffset(key: string): number {
    return this.buffer.readOffset(`${OFFSET_NS}:${key}`)
  }

  private saveOffset(key: string, value: number): void {
    this.buffer.writeOffset(`${OFFSET_NS}:${key}`, value)
  }

  /** conversation_summaries is often empty (only populated for some Cursor
   *  versions/modes) — a missing title just falls back to null. */
  private lookupTitle(conversationId: string): string | null {
    try {
      const row = this.db!
        .prepare('SELECT title FROM conversation_summaries WHERE conversationId = ?')
        .get(conversationId) as { title: string | null } | undefined
      return row?.title?.trim() || null
    } catch {
      return null
    }
  }

  private ensureTaskStarted(conversationId: string, createdAt: number): void {
    if (this.seenConversations.has(conversationId)) return
    this.seenConversations.add(conversationId)
    this.buffer.offerTaskStart({
      taskId: `CURSOR:${conversationId}`,
      sourceTool: this.sourceTool,
      title: this.lookupTitle(conversationId),
      startedAt: new Date(createdAt).toISOString(),
      projectContext: {
        projectRoot: null,
        repoName: null,
        gitBranch: null,
        gitCommit: null,
        remoteUrl: null,
      },
    })
  }

  /** Poll ai_code_hashes incrementally, bounded per cycle so a large existing
   *  history (tens of thousands of rows on an established install) backfills
   *  gradually across poll cycles instead of in one burst.
   *
   *  Paginates by `rowid`, not `createdAt`: verified against a real local DB
   *  that `createdAt` is NOT unique — up to ~300 rows share the exact same
   *  millisecond timestamp (bulk edits land in one tick). Using it as the
   *  incremental cursor got permanently stuck re-fetching the same
   *  arbitrarily-ordered tied rows forever (SQLite gives no ordering
   *  guarantee among ties), which also meant the same taskStart/EDIT items
   *  were re-emitted every poll instead of the offset ever advancing.
   *  `rowid` is implicit and unique on this table (a plain rowid table; its
   *  declared PK is a TEXT hash, not INTEGER, so rowid is a distinct column). */
  private pollHashes(): void {
    const lastRowid = this.lastOffset('hashes_last_rowid')
    let maxRowid = lastRowid
    try {
      const stmt = this.db!.prepare(
        `SELECT rowid, source, fileExtension, fileName, requestId, conversationId, model, createdAt
         FROM ai_code_hashes WHERE rowid > ? ORDER BY rowid LIMIT 500`,
      )
      const rows = stmt.all(lastRowid) as unknown as AiCodeHashRow[]
      for (const row of rows) {
        const conversationId = row.conversationId || 'unknown'
        const taskId = `CURSOR:${conversationId}`
        this.ensureTaskStarted(conversationId, row.createdAt)
        this.buffer.offerItem({
          type: 'EVENT',
          taskId,
          eventType: 'EDIT',
          occurredAt: new Date(row.createdAt).toISOString(),
          payload: {
            source: row.source,
            fileName: row.fileName ? basename(row.fileName) : null,
            fileExtension: row.fileExtension,
            model: row.model,
            requestId: row.requestId,
          },
        })
        if (row.rowid > maxRowid) maxRowid = row.rowid
      }
    } catch (err) {
      console.error(`[retrysight-lite] Cursor SQLite: ai_code_hashes poll error: ${err}`)
    }
    if (maxRowid > lastRowid) this.saveOffset('hashes_last_rowid', maxRowid)
  }
}
