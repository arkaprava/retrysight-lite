#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const base = (process.env.RETRYSIGHT_URL || 'http://127.0.0.1:18081').replace(/\/$/, '')

function resolveAgentKey() {
  const fromEnv = process.env.AGENT_API_KEY?.trim()
  if (fromEnv && fromEnv !== 'dev-agent-key') return fromEnv
  const candidates = [
    process.env.RETRYSIGHT_DATA_DIR && join(process.env.RETRYSIGHT_DATA_DIR, 'agent-api-key'),
    join(root, 'manager/data/agent-api-key'),
    join(root, 'data/agent-api-key'),
  ].filter(Boolean)
  for (const p of candidates) {
    if (existsSync(p)) {
      const v = readFileSync(p, 'utf8').trim()
      if (v) return v
    }
  }
  return fromEnv || 'dev-agent-key'
}

const apiKey = resolveAgentKey()

const heartbeat = {
  name: 'seed-agent',
  developerEmail: 'seed@local',
  hostname: 'seed-host',
  osUsername: 'seed',
  installedCollectors: ['CURSOR', 'CLAUDE_CODE'],
}

const taskId = `CURSOR:demo-${Date.now()}`
const now = new Date().toISOString()
const t = (offsetSec) => new Date(Date.now() + offsetSec * 1000).toISOString()

const batch = {
  heartbeat,
  taskStarts: [
    {
      taskId,
      sourceTool: 'CURSOR',
      title: 'Seed demo task',
      startedAt: t(-120),
      projectContext: { repoName: 'RetrySightLite', projectRoot: root },
    },
  ],
  items: [
    { type: 'EVENT', taskId, eventType: 'SESSION_START', occurredAt: t(-120) },
    { type: 'EVENT', taskId, eventType: 'EDIT', occurredAt: t(-90), payload: { note: 'first edit' } },
    { type: 'EVENT', taskId, eventType: 'TEST_FAIL', occurredAt: t(-60) },
    {
      type: 'TOKEN_USAGE',
      taskId,
      model: 'gpt-demo',
      inputTokens: 1200,
      outputTokens: 400,
      occurredAt: t(-30),
    },
    { type: 'TASK_COMPLETE', taskId, status: 'COMPLETED', endedAt: now },
  ],
}

const hb = await fetch(`${base}/api/v1/ingest/heartbeat`, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    'x-agent-api-key': apiKey,
  },
  body: JSON.stringify(heartbeat),
})
if (!hb.ok) {
  console.error('heartbeat failed', hb.status, await hb.text())
  process.exit(1)
}
const hbJson = await hb.json()
console.log('heartbeat', hbJson)

const res = await fetch(`${base}/api/v1/ingest/batch`, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    'x-agent-api-key': apiKey,
    'x-agent-id': hbJson.agentId,
  },
  body: JSON.stringify(batch),
})
if (!res.ok) {
  console.error('batch failed', res.status, await res.text())
  process.exit(1)
}
console.log('batch', await res.json())
console.log('Seeded task', taskId)
