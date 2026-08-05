#!/usr/bin/env node
/**
 * smoke-test.mjs — API smoke test for RetrySight Lite
 *
 * Validates all REST + GraphQL endpoints that the TUI and API consumers rely on.
 * Launches the app in headless mode, runs checks, and exits.
 *
 * Usage:
 *   node --experimental-sqlite smoke-test.mjs
 */

import { spawn } from 'node:child_process'
import { randomBytes, randomInt } from 'node:crypto'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SMOKE_PORT = process.env.RETRYSIGHT_URL
  ? new URL(process.env.RETRYSIGHT_URL).port || '18081'
  : String(randomInt(40000, 50000))
const BASE = (process.env.RETRYSIGHT_URL || `http://127.0.0.1:${SMOKE_PORT}`).replace(/\/$/, '')
// Ephemeral credentials for this run — never hardcode or reuse real tokens.
const ADMIN_TOKEN = `adm_${randomBytes(24).toString('hex')}`
const AGENT_API_KEY = `asl_${randomBytes(24).toString('hex')}`
// Hermetic workspace: temp DB + collector offsets so the test never touches real data.
const TMP = mkdtempSync(join(tmpdir(), 'retrysight-lite-smoke-'))
const DB_PATH = join(TMP, 'retrysight-lite.db')
const COLLECTOR_DIR = join(TMP, 'collector-data')

let failed = 0
let passed = 0

function ok(label) { passed++; console.log(`  ✓ ${label}`) }
function fail(label, detail) { failed++; console.log(`  ✗ ${label}: ${detail}`) }

async function test(label, fn) {
  const start = Date.now()
  try {
    const result = await fn()
    ok(`${label} (${Date.now() - start}ms)`)
    return result
  } catch (e) {
    fail(label, e.message || e)
    return null
  }
}

function assert(label, expr) {
  if (!expr) throw new Error(`assertion failed: ${label}`)
}

// ── Helpers ──────────────────────────────────────────────────────────

async function api(path, opts = {}) {
  const url = path.startsWith('http') ? path : `${BASE}${path}`
  const headers = { ...opts.headers }
  if (!opts.noAuth) {
    headers['Authorization'] = `Bearer ${ADMIN_TOKEN}`
  }
  const res = await fetch(url, { ...opts, headers })
  const text = await res.text()
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${path}: ${text.slice(0, 200)}`)
  }
  try { return JSON.parse(text) } catch { return text }
}

async function gql(query, variables = {}) {
  const res = await fetch(`${BASE}/graphql`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${ADMIN_TOKEN}`,
    },
    body: JSON.stringify({ query, variables }),
  })
  const body = await res.json()
  if (body.errors) throw new Error(body.errors.map(e => e.message).join('; '))
  return body.data
}

// ── Launch ─────────────────────────────────────────────────────────────

const proc = spawn(resolve(__dirname, 'node_modules/.bin/tsx'), [
  resolve(__dirname, 'src/index.ts'),
  '--headless',
], {
  cwd: __dirname,
  stdio: ['ignore', 'pipe', 'pipe'],
  env: {
    ...process.env,
    RETRYSIGHT_DATA_DIR: TMP,
    RETRYSIGHT_DB_PATH: DB_PATH,
    RETRYSIGHT_COLLECTOR_DIR: COLLECTOR_DIR,
    RETRYSIGHT_PORT: SMOKE_PORT,
    RETRYSIGHT_HOST: '127.0.0.1',
    RETRYSIGHT_ADMIN_TOKEN: ADMIN_TOKEN,
    AGENT_API_KEY: AGENT_API_KEY,
    RETRYSIGHT_COLLECTORS: '0',
  },
})

let procStdout = ''
let procStderr = ''
proc.stdout.on('data', (d) => { procStdout += d.toString() })
proc.stderr.on('data', (d) => { procStderr += d.toString() })

// ── Wait for ready ─────────────────────────────────────────────────────

async function waitForReady(maxMs = 15_000) {
  const start = Date.now()
  while (Date.now() - start < maxMs) {
    try {
      const res = await fetch(`${BASE}/api/v1/health`, { signal: AbortSignal.timeout(2000) })
      if (res.ok) return
    } catch { /* keep waiting */ }
    await new Promise(r => setTimeout(r, 300))
  }
  throw new Error(`Server did not start within ${maxMs}ms\n  stdout: ${procStdout.slice(-300)}\n  stderr: ${procStderr.slice(-300)}`)
}

// ── Main ───────────────────────────────────────────────────────────────

async function main() {
  console.log('\n── Launching RetrySight Lite (headless) ──')
  try {
    await waitForReady()
    ok('server started')
  } catch (e) {
    fail('server start', e.message)
    cleanupAndExit()
    return
  }

  console.log('\n── Health & Public Endpoints ──')
  await test('GET /api/v1/health (public)', async () => {
    const data = await api('/api/v1/health', { noAuth: true })
    assert('status is ok', data.status === 'ok')
    assert('service is retrysight-lite', data.service === 'retrysight-lite')
    return data
  })

  console.log('\n── Dashboard (REST) ──')
  await test('GET /api/v1/dashboard', async () => {
    const data = await api('/api/v1/dashboard')
    assert('has taskCount', typeof data.taskCount === 'number')
    assert('has activeCount', typeof data.activeCount === 'number')
    assert('has completedCount', typeof data.completedCount === 'number')
    assert('has totalRetries', typeof data.totalRetries === 'number')
    assert('has byTool array', Array.isArray(data.byTool))
    assert('has byStatus array', Array.isArray(data.byStatus))
    assert('has retryTrend array', Array.isArray(data.retryTrend))
    assert('has topRetryTasks array', Array.isArray(data.topRetryTasks))
    assert('has byModel array', Array.isArray(data.byModel))
    assert('has availableTools', Array.isArray(data.availableTools))
    assert('has availableAgents', Array.isArray(data.availableAgents))
    return data
  })

  await test('GET /api/v1/dashboard?sourceTool filter', async () => {
    const data = await api('/api/v1/dashboard?sourceTool=cursor')
    return data
  })

  await test('GET /api/v1/dashboard?from/to date filter', async () => {
    const data = await api('/api/v1/dashboard?from=2026-01-01T00:00:00Z&to=2026-12-31T23:59:59Z')
    assert('returns within range', typeof data.taskCount === 'number')
    return data
  })

  console.log('\n── Agents (REST) ──')
  await test('GET /api/v1/agents', async () => {
    const data = await api('/api/v1/agents')
    assert('is array', Array.isArray(data))
    return data
  })

  const _agentList = await test('GET /api/v1/agents (returns valid items)', async () => {
    const data = await api('/api/v1/agents')
    for (const a of data) {
      assert('agent has id', typeof a.id === 'string')
      assert('agent has name', typeof a.name === 'string')
      assert('agent has hostname', typeof a.hostname === 'string')
      assert('agent has last_heartbeat_at or stale', typeof a.last_heartbeat_at === 'string' || typeof a.stale === 'boolean')
    }
    return data
  })

  if (_agentList && _agentList.length > 0) {
    const firstId = _agentList[0].id
    await test(`GET /api/v1/agents/${firstId}`, async () => {
      const data = await api(`/api/v1/agents/${firstId}`)
      assert('returns matching id', data.id === firstId)
      assert('has name', typeof data.name === 'string')
      // REST returns raw snake_case DB fields
      assert('has developer_email or developerEmail', typeof data.developer_email === 'string' || typeof data.developerEmail === 'string')
      return data
    })
  }

  console.log('\n── Tasks (REST) ──')
  await test('GET /api/v1/tasks', async () => {
    const data = await api('/api/v1/tasks')
    assert('has items array', Array.isArray(data.items))
    assert('has totalCount', typeof data.totalCount === 'number')
    return data
  })

  const _taskList = await test('GET /api/v1/tasks pagination params', async () => {
    const data = await api('/api/v1/tasks?page=0&size=5&minRetries=1')
    assert('items is array', Array.isArray(data.items))
    assert('totalCount is number', typeof data.totalCount === 'number')
    return data
  })

  if (_taskList && _taskList.items.length > 0) {
    const firstId = _taskList.items[0].id
    await test(`GET /api/v1/tasks/${firstId} (with events + timeline)`, async () => {
      const data = await api(`/api/v1/tasks/${firstId}`)
      assert('has events array', Array.isArray(data.events))
      assert('has timeline array', Array.isArray(data.timeline))
      assert('id matches', data.id === firstId)
      return data
    })
  }

  console.log('\n── Collectors (REST) ──')
  await test('GET /api/v1/collectors', async () => {
    const data = await api('/api/v1/collectors')
    assert('has enabled flag', typeof data.enabled === 'boolean')
    assert('has running flag', typeof data.running === 'boolean')
    assert('has collectors array', Array.isArray(data.collectors))
    return data
  })

  console.log('\n── MCP Config (REST) ──')
  await test('GET /api/v1/mcp/config', async () => {
    const data = await api('/api/v1/mcp/config')
    assert('has transport', typeof data.transport === 'string')
    assert('has command', typeof data.command === 'string')
    assert('has args array', Array.isArray(data.args))
    assert('has configJson', typeof data.configJson === 'string')
    assert('has endpointHint', typeof data.endpointHint === 'string')
    return data
  })

  console.log('\n── API Keys (REST) ──')
  let _createdKeyId = null
  await test('POST /api/v1/api-keys creates key', async () => {
    const data = await api('/api/v1/api-keys', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'smoke-test-key' }),
    })
    assert('has id', typeof data.id === 'string')
    assert('has keyPrefix', typeof data.keyPrefix === 'string')
    assert('has rawKey', typeof data.rawKey === 'string')
    assert('key starts with asl_', data.rawKey.startsWith('asl_'))
    _createdKeyId = data.id
    return data
  })

  console.log('\n── GraphQL ──')
  await test('GraphQL { health }', async () => {
    const data = await gql('{ health }')
    assert('health is ok', data.health === 'ok')
    return data
  })

  await test('GraphQL { dashboardSummary }', async () => {
    const data = await gql(`{
      dashboardSummary {
        taskCount activeCount completedCount totalRetries
        byTool { sourceTool count }
        byStatus { status count }
        retryTrend { day retries tasks }
        topRetryTasks { id title retryCount }
        byModel { model inputTokens outputTokens estimatedCostUsd }
      }
    }`)
    assert('has taskCount', typeof data.dashboardSummary.taskCount === 'number')
    assert('byTool is array', Array.isArray(data.dashboardSummary.byTool))
    assert('byStatus is array', Array.isArray(data.dashboardSummary.byStatus))
    assert('retryTrend is array', Array.isArray(data.dashboardSummary.retryTrend))
    assert('topRetryTasks is array', Array.isArray(data.dashboardSummary.topRetryTasks))
    return data
  })

  await test('GraphQL { agents }', async () => {
    const data = await gql(`{ agents { id name hostname stale } }`)
    assert('agents is array', Array.isArray(data.agents))
    return data
  })

  await test('GraphQL { tasks { items { id status retryCount } totalCount } }', async () => {
    const data = await gql(`{
      tasks(page: 0, size: 10) {
        items { id status retryCount title sourceTool }
        totalCount
      }
    }`)
    assert('items is array', Array.isArray(data.tasks.items))
    assert('totalCount is number', typeof data.tasks.totalCount === 'number')
    return data
  })

  if (_taskList && _taskList.items.length > 0) {
    const firstId = _taskList.items[0].id
    await test(`GraphQL { task(id: "${firstId}") { ... events timeline } }`, async () => {
      const data = await gql(`{
        task(id: "${firstId}") {
          id title status retryCount sourceTool
          events { id eventType occurredAt }
          timeline { id eventType summary isRetrySignal }
        }
      }`)
      assert('task id matches', data.task.id === firstId)
      assert('events is array', Array.isArray(data.task.events))
      assert('timeline is array', Array.isArray(data.task.timeline))
      return data
    })
  }

  await test('GraphQL { collectors { enabled running collectors } }', async () => {
    const data = await gql(`{ collectors { enabled running collectors } }`)
    assert('has enabled', typeof data.collectors.enabled === 'boolean')
    assert('has running', typeof data.collectors.running === 'boolean')
    assert('collectors is array', Array.isArray(data.collectors.collectors))
    return data
  })

  await test('GraphQL { mcpConfig { transport command args endpointHint } }', async () => {
    const data = await gql(`{ mcpConfig { transport command args endpointHint } }`)
    assert('has transport', typeof data.mcpConfig.transport === 'string')
    assert('has command', typeof data.mcpConfig.command === 'string')
    assert('has args array', Array.isArray(data.mcpConfig.args))
    assert('has endpointHint', typeof data.mcpConfig.endpointHint === 'string')
    return data
  })

  await test('GraphQL mutation createApiKey', async () => {
    const data = await gql(`
      mutation CreateKey($name: String!) {
        createApiKey(name: $name) {
          key { id name keyPrefix active }
          rawKey
        }
      }
    `, { name: 'gql-smoke-test' })
    assert('has key.id', typeof data.createApiKey.key.id === 'string')
    assert('has rawKey', typeof data.createApiKey.rawKey === 'string')
    assert('key is active', data.createApiKey.key.active === true)
    return data
  })

  // ── Ingest endpoint test (agent API key auth) ──
  console.log('\n── Ingest (agent-key auth) ──')
  await test('POST /api/v1/ingest/heartbeat', async () => {
    const res = await fetch(`${BASE}/api/v1/ingest/heartbeat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Agent-Api-Key': AGENT_API_KEY,
        'X-Agent-Id': 'smoke-test-agent',
      },
      body: JSON.stringify({
        name: 'smoke-test-agent',
        developerEmail: 'smoke@test.local',
        hostname: 'smoke-host',
      }),
    })
    const data = await res.json()
    // heartbeat returns { agentId, status } on success
    assert('has status or agentId', data.status === 'ok' || typeof data.agentId === 'string')
    return data
  })

  // ── Error handling tests ──
  console.log('\n── Error Handling ──')
  await test('401 on missing admin token', async () => {
    const res = await fetch(`${BASE}/api/v1/dashboard`)
    assert('returns 401', res.status === 401)
    return res.status
  })

  await test('401 on wrong admin token', async () => {
    const res = await fetch(`${BASE}/api/v1/dashboard`, {
      headers: { 'Authorization': 'Bearer wrong-token' },
    })
    assert('returns 401', res.status === 401)
    return res.status
  })

  await test('404 on unknown agent', async () => {
    const res = await fetch(`${BASE}/api/v1/agents/nonexistent-id`, {
      headers: { 'Authorization': `Bearer ${ADMIN_TOKEN}` },
    })
    assert('returns 404', res.status === 404)
    return res.status
  })

  await test('404 on unknown task', async () => {
    const res = await fetch(`${BASE}/api/v1/tasks/nonexistent-task`, {
      headers: { 'Authorization': `Bearer ${ADMIN_TOKEN}` },
    })
    assert('returns 404', res.status === 404)
    return res.status
  })

  await test('public health check does not need auth', async () => {
    const res = await fetch(`${BASE}/api/v1/health`)
    assert('returns 200', res.status === 200)
    return res.status
  })

  // ── Summary ──
  console.log('')
  const total = passed + failed
  console.log(`── Results: ${passed}/${total} passed, ${failed} failed ──`)

  cleanupAndExit()
}

function cleanupAndExit() {
  proc.kill('SIGTERM')
  setTimeout(() => proc.kill('SIGKILL'), 2000)
  try { rmSync(TMP, { recursive: true, force: true }) } catch { /* ignore */ }
  process.exit(failed > 0 ? 1 : 0)
}

main().catch((e) => {
  console.error('\nUnhandled error:', e.message)
  cleanupAndExit()
})
