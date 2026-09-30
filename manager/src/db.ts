// SPDX-License-Identifier: Apache-2.0

import { DatabaseSync } from 'node:sqlite'
import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto'
import { chmodSync, existsSync } from 'node:fs'
import { config } from './config.js'

export type AgentRow = {
  id: string
  name: string
  developer_email: string
  os_username: string | null
  display_name: string | null
  git_email: string | null
  hostname: string
  last_heartbeat_at: string | null
  installed_collectors: string | null
  registered_by_key_hash: string | null
  created_at: string
}

export type TaskRow = {
  id: string
  agent_id: string
  source_tool: string
  status: string
  title: string | null
  retry_count: number
  input_tokens: number
  output_tokens: number
  started_at: string
  ended_at: string | null
  project_root: string | null
  repo_name: string | null
  git_branch: string | null
  git_commit: string | null
  remote_url: string | null
  created_at: string
  updated_at: string
}

let db: DatabaseSync

function verifyScrypt(raw: string, stored: string): boolean {
  // Format: s1:<salt_hex>:<hash_hex>
  const parts = stored.split(':')
  if (parts.length !== 3 || parts[0] !== 's1') return false
  try {
    const salt = Buffer.from(parts[1], 'hex')
    const expectedHash = Buffer.from(parts[2], 'hex')
    if (salt.length !== 16 || expectedHash.length !== 32) return false
    const derived = scryptSync(raw, salt, 32, { N: 16384, r: 8, p: 1, maxmem: 32 * 1024 * 1024 })
    if (derived.length !== expectedHash.length) return false
    return timingSafeEqual(derived, expectedHash)
  } catch {
    return false
  }
}

/** Legacy SHA-256 verification for keys hashed before the migration to scrypt. */
function verifySha256(raw: string, stored: string): boolean {
  try {
    const hash = createHash('sha256').update(raw).digest('hex')
    const storedBuf = Buffer.from(stored, 'hex')
    const hashBuf = Buffer.from(hash, 'hex')
    if (storedBuf.length !== hashBuf.length) return false
    return timingSafeEqual(storedBuf, hashBuf)
  } catch {
    return false
  }
}

/** Keep DB files private (0600) even when created before this hardening. */
function hardenDbFilePerms(): void {
  for (const p of [config.dbPath, `${config.dbPath}-wal`, `${config.dbPath}-shm`]) {
    try {
      if (existsSync(p)) chmodSync(p, 0o600)
    } catch {
      /* best effort */
    }
  }
}

export function getDb(): DatabaseSync {
  if (!db) {
    db = new DatabaseSync(config.dbPath)
    db.exec('PRAGMA journal_mode = WAL')
    db.exec('PRAGMA foreign_keys = ON')
    migrate(db)
    hardenDbFilePerms()
  }
  return db
}

function migrate(database: DatabaseSync) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS agents (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      developer_email TEXT NOT NULL,
      os_username TEXT,
      display_name TEXT,
      git_email TEXT,
      hostname TEXT NOT NULL,
      last_heartbeat_at TEXT,
      installed_collectors TEXT,
      registered_by_key_hash TEXT,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      agent_id TEXT NOT NULL REFERENCES agents(id),
      source_tool TEXT NOT NULL,
      status TEXT NOT NULL,
      title TEXT,
      retry_count INTEGER NOT NULL DEFAULT 0,
      input_tokens INTEGER NOT NULL DEFAULT 0,
      output_tokens INTEGER NOT NULL DEFAULT 0,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      project_root TEXT,
      repo_name TEXT,
      git_branch TEXT,
      git_commit TEXT,
      remote_url TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tasks_agent ON tasks(agent_id);
    CREATE INDEX IF NOT EXISTS idx_tasks_started ON tasks(started_at);

    CREATE TABLE IF NOT EXISTS task_events (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL REFERENCES tasks(id),
      event_type TEXT NOT NULL,
      payload_json TEXT,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_events_task ON task_events(task_id, occurred_at);

    CREATE TABLE IF NOT EXISTS api_keys (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      key_hash TEXT NOT NULL,
      key_prefix TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'agent',
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      last_used_at TEXT,
      revoked_at TEXT,
      expires_at TEXT
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `)

  // Migrate: add columns that were added in later schema versions
  for (const stmt of [
    'ALTER TABLE api_keys ADD COLUMN expires_at TEXT',
    'ALTER TABLE agents ADD COLUMN registered_by_key_hash TEXT',
  ]) {
    try { database.exec(stmt) } catch { /* column already exists — ignore */ }
  }

  const existing = database
    .prepare('SELECT id FROM api_keys WHERE key_prefix = ?')
    .get(config.agentApiKey.slice(0, 8))
  if (!existing) {
    insertApiKey(database, 'default-agent', config.agentApiKey, 'agent')
  }
}

export function hashKey(raw: string): string {
  // scrypt: N=16384, r=8, p=1 (OWASP minimum for interactive use)
  const salt = randomBytes(16)
  const derived = scryptSync(raw, salt, 32, { N: 16384, r: 8, p: 1, maxmem: 32 * 1024 * 1024 })
  return `s1:${salt.toString('hex')}:${derived.toString('hex')}`
}

export function insertApiKey(
  database: DatabaseSync,
  name: string,
  rawKey: string,
  role = 'agent',
  expiresAt?: string,
): { id: string; keyPrefix: string } {
  const id = cryptoRandomId()
  const keyPrefix = rawKey.slice(0, 8)
  database
    .prepare(
      `INSERT INTO api_keys (id, name, key_hash, key_prefix, role, active, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?, 1, ?, ?)`,
    )
    .run(id, name, hashKey(rawKey), keyPrefix, role, nowIso(), expiresAt ?? null)
  return { id, keyPrefix }
}

export function verifyApiKey(raw: string): string | null {
  const database = getDb()
  // Narrow candidates by the stored 8-char key prefix before scrypt verification.
  const rows = database
    .prepare(
      'SELECT key_hash FROM api_keys WHERE active = 1 AND revoked_at IS NULL AND key_prefix = ? AND (expires_at IS NULL OR expires_at > ?)',
    )
    .all(raw.slice(0, 8), nowIso()) as { key_hash: string }[]
  // Try scrypt first, fall back to SHA-256 for legacy keys
  for (const r of rows) {
    if (r.key_hash.startsWith('s1:')) {
      if (verifyScrypt(raw, r.key_hash)) return r.key_hash
    } else {
      // Legacy SHA-256 key — verify and re-hash with scrypt on the fly
      if (verifySha256(raw, r.key_hash)) {
        const newHash = hashKey(raw)
        getDb()
          .prepare('UPDATE api_keys SET key_hash = ? WHERE key_hash = ?')
          .run(newHash, r.key_hash)
        return newHash
      }
    }
  }
  return null
}

export function nowIso(): string {
  return new Date().toISOString()
}

export function cryptoRandomId(): string {
  return randomBytes(16).toString('hex')
}

/** Delete tasks, events, and events for orphaned tasks older than `days`. */
export function cleanupOldData(days: number): { deletedTasks: number; deletedEvents: number } {
  if (days <= 0) return { deletedTasks: 0, deletedEvents: 0 }
  const database = getDb()
  const cutoff = new Date(Date.now() - days * 86_400_000).toISOString()
  // Delete events for tasks older than cutoff — but never a still-ACTIVE task:
  // an old `created_at` doesn't mean abandoned, just long-running, and deleting
  // it out from under the agent still reporting to it would corrupt its state.
  const deletedEvents = Number(
    database
      .prepare(
        `DELETE FROM task_events WHERE task_id IN (
           SELECT id FROM tasks WHERE created_at < ? AND status != 'ACTIVE'
         )`,
      )
      .run(cutoff).changes,
  )
  // Delete tasks older than cutoff, excluding ACTIVE ones (see above)
  const deletedTasks = Number(
    database
      .prepare(`DELETE FROM tasks WHERE created_at < ? AND status != 'ACTIVE'`)
      .run(cutoff).changes,
  )
  if (deletedTasks > 0 || deletedEvents > 0) {
    console.log(
      `[retrysight-lite] Cleaned up ${deletedTasks} tasks and ${deletedEvents} events older than ${days}d`,
    )
  }
  return { deletedTasks, deletedEvents }
}

/** Generic key/value settings row, shared by collector configs, the cost
 *  budget, and any future admin-configurable value that shouldn't require an
 *  env var + restart. */
export function getSetting(key: string): string | null {
  const row = getDb()
    .prepare('SELECT value FROM settings WHERE key = ?')
    .get(key) as { value: string } | undefined
  return row?.value ?? null
}

export function setSetting(key: string, value: string): void {
  getDb()
    .prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)')
    .run(key, value)
}

export function deleteSetting(key: string): void {
  getDb().prepare('DELETE FROM settings WHERE key = ?').run(key)
}

export function generateRawKey(): string {
  return `asl_${randomBytes(24).toString('hex')}`
}
