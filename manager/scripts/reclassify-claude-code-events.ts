// SPDX-License-Identifier: Apache-2.0
//
// One-off backfill for the retry_count / token-usage overcounting bug in
// FlexibleLogCollector (see collectors/flexible-collector.ts): before that
// fix, real Claude Code CLI transcript lines (and any other tool sharing
// its JSONL code path) were almost always misclassified, inflating
// task_events.event_type to 'EDIT' and tasks.retry_count along with it —
// and separately, `message.usage` (where real Claude Code token counts
// actually live) was never read at all, so those lines never produced a
// TOKEN_USAGE row either.
//
// This does NOT re-read the source .jsonl files or touch
// collector-data/offsets.json. EventBuffer's offsets already point past
// those bytes, and ingest.ts's insert path has no dedupe key — resetting
// offsets and re-polling would insert duplicate task_events rows and
// double-bump retry_count on top of the existing (wrong) totals. Instead,
// task_events.payload_json already holds the original raw JSONL object for
// every non-TOKEN_USAGE row (see ingest.ts's EVENT branch), so this
// re-runs the SAME classification the live collector now uses
// (`classifyJsonlEvent`, exported from flexible-collector.ts specifically
// so the two can't drift) against that stored payload.
//
// A line that both is a real activity (edit/tool call) AND carries token
// usage — true for most real Claude Code assistant turns — needs two
// separate historical facts recorded, matching what the fixed live
// collector now does (one EVENT row + one TOKEN_USAGE row per such line).
// Since the original row can only hold one event_type, this backfill
// leaves it holding the corrected activity classification and, when the
// line also carried usage, additionally inserts a new twin TOKEN_USAGE row
// with a deterministic id (`${row.id}:token-usage`, via INSERT OR IGNORE)
// derived from the token-bearing row it recovers usage from. Each task's
// retry_count/input_tokens/output_tokens is then set to a freshly computed
// total (always a full replace, never an increment), which is what makes
// re-running this script safe.
//
// Usage:
//   npx tsx scripts/reclassify-claude-code-events.ts            # dry run, prints a summary, writes nothing
//   npx tsx scripts/reclassify-claude-code-events.ts --apply    # backs up the db file, then writes changes in one transaction

import { copyFileSync } from 'node:fs'
import { getDb } from '../src/db.js'
import { config } from '../src/config.js'
import { classifyJsonlEvent } from '../src/collectors/flexible-collector.js'

const RETRY_TYPES = new Set(['EDIT', 'TEST_FAIL', 'DIFF_REJECTED', 'COMPACTION', 'COMMAND_FAILED', 'TOOL_ERROR'])

// Tools that route through FlexibleLogCollector's JSONL path and are
// therefore in-scope for this bug. CURSOR now ingests via a dedicated
// sqlite collector (its jsonl fallback is a no-op in practice); WARP's
// file-based collector reads plaintext, not jsonl, so neither is affected.
const AFFECTED_SOURCE_TOOLS = ['CLAUDE_CODE', 'WINDSURF', 'CLINE', 'AIDER', 'CONTINUE', 'GITHUB_COPILOT']

type TaskRow = {
  id: string
  source_tool: string
  retry_count: number
  input_tokens: number
  output_tokens: number
}
type EventRow = { id: string; event_type: string; payload_json: string | null; occurred_at: string }

function numOrZero(obj: Record<string, unknown> | undefined, ...keys: string[]): number {
  if (!obj) return 0
  for (const key of keys) {
    const v = obj[key]
    if (typeof v === 'number' && Number.isFinite(v)) return v
  }
  return 0
}

function main() {
  const apply = process.argv.includes('--apply')
  const db = getDb()

  if (apply) {
    const backupPath = `${config.dbPath}.before-reclassify-${Date.now()}`
    copyFileSync(config.dbPath, backupPath)
    console.log(`Backed up database to ${backupPath}`)
  }

  const tasks = db
    .prepare(
      `SELECT id, source_tool, retry_count, input_tokens, output_tokens
       FROM tasks WHERE source_tool IN (${AFFECTED_SOURCE_TOOLS.map(() => '?').join(',')})`,
    )
    .all(...AFFECTED_SOURCE_TOOLS) as TaskRow[]

  console.log(`Found ${tasks.length} task(s) from affected source tools: ${AFFECTED_SOURCE_TOOLS.join(', ')}`)

  const updateEventType = db.prepare('UPDATE task_events SET event_type = ? WHERE id = ?')
  const insertTokenUsageTwin = db.prepare(
    `INSERT OR IGNORE INTO task_events (id, task_id, event_type, payload_json, occurred_at, created_at)
     VALUES (?, ?, 'TOKEN_USAGE', ?, ?, ?)`,
  )
  const updateTaskCounts = db.prepare(
    'UPDATE tasks SET retry_count = ?, input_tokens = ?, output_tokens = ?, updated_at = ? WHERE id = ?',
  )

  let tasksChanged = 0
  let rowsReclassified = 0
  let tokenRowsCreated = 0
  let rowsUnparsed = 0

  const run = () => {
    for (const task of tasks) {
      const events = db
        .prepare('SELECT id, event_type, payload_json, occurred_at FROM task_events WHERE task_id = ?')
        .all(task.id) as EventRow[]
      const existingIds = new Set(events.map((e) => e.id))

      let newRetryCount = 0
      let newInputTokens = 0
      let newOutputTokens = 0

      for (const row of events) {
        if (row.event_type === 'TOKEN_USAGE') {
          // An already-correct TOKEN_USAGE row (recorded before this bug,
          // or a twin this script itself created on an earlier run) stores
          // the slim {model, inputTokens, outputTokens} shape ingest.ts
          // normally writes.
          if (row.payload_json) {
            try {
              const parsed = JSON.parse(row.payload_json) as { inputTokens?: number; outputTokens?: number }
              newInputTokens += parsed.inputTokens ?? 0
              newOutputTokens += parsed.outputTokens ?? 0
            } catch {
              rowsUnparsed += 1
            }
          }
          continue
        }

        if (!row.payload_json) {
          // No raw payload to reclassify from (e.g. a plaintext LOG_LINE
          // row) — leave the row as-is but still count it correctly.
          if (RETRY_TYPES.has(row.event_type)) newRetryCount += 1
          continue
        }

        let payload: Record<string, unknown>
        try {
          payload = JSON.parse(row.payload_json) as Record<string, unknown>
        } catch {
          // Payload was truncated (task_events.payload_json is capped at
          // MAX_PAYLOAD_JSON bytes in ingest.ts) or otherwise unparsable —
          // can't reclassify; leave the existing event_type's verdict.
          rowsUnparsed += 1
          if (RETRY_TYPES.has(row.event_type)) newRetryCount += 1
          continue
        }

        const { eventType, usage, message, isTokenUsageLine } = classifyJsonlEvent(payload, task.source_tool)

        if (eventType !== row.event_type) {
          rowsReclassified += 1
          if (apply) updateEventType.run(eventType, row.id)
        }
        if (RETRY_TYPES.has(eventType)) newRetryCount += 1

        if (isTokenUsageLine) {
          const twinId = `${row.id}:token-usage`
          if (!existingIds.has(twinId)) {
            // First time seeing this line's usage recovered — count it now
            // and (on --apply) create its twin row so a re-run recognizes
            // it via the `event_type === 'TOKEN_USAGE'` branch above instead
            // of double-counting it from here.
            newInputTokens += numOrZero(usage, 'input_tokens', 'inputTokens')
            newOutputTokens += numOrZero(usage, 'output_tokens', 'outputTokens')
            if (apply) {
              const model =
                (typeof payload.model === 'string' && payload.model) ||
                (message && typeof message.model === 'string' && message.model) ||
                null
              const slim = JSON.stringify({
                model,
                inputTokens: numOrZero(usage, 'input_tokens', 'inputTokens'),
                outputTokens: numOrZero(usage, 'output_tokens', 'outputTokens'),
              })
              insertTokenUsageTwin.run(twinId, task.id, slim, row.occurred_at, new Date().toISOString())
            }
            tokenRowsCreated += 1
          }
        }
      }

      const taskChanged =
        newRetryCount !== task.retry_count ||
        newInputTokens !== task.input_tokens ||
        newOutputTokens !== task.output_tokens

      if (taskChanged) {
        tasksChanged += 1
        console.log(
          `${task.id}: retry_count ${task.retry_count} -> ${newRetryCount}, ` +
            `input_tokens ${task.input_tokens} -> ${newInputTokens}, ` +
            `output_tokens ${task.output_tokens} -> ${newOutputTokens}`,
        )
        if (apply) {
          updateTaskCounts.run(newRetryCount, newInputTokens, newOutputTokens, new Date().toISOString(), task.id)
        }
      }
    }
  }

  if (apply) {
    db.exec('BEGIN')
    try {
      run()
      db.exec('COMMIT')
    } catch (err) {
      db.exec('ROLLBACK')
      throw err
    }
  } else {
    run()
  }

  console.log(
    `\n${apply ? 'Applied' : 'Would apply'}: ${tasksChanged} task(s) changed, ${rowsReclassified} event row(s) reclassified, ` +
      `${tokenRowsCreated} new TOKEN_USAGE row(s) recovered` +
      (rowsUnparsed ? `, ${rowsUnparsed} row(s) had unparsable/missing payload_json` : ''),
  )
  if (!apply) {
    console.log('Dry run only — nothing was written. Re-run with --apply to write changes (a timestamped .db backup is made first).')
  }
}

main()
