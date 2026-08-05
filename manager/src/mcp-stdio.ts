#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0

/**
 * RetrySight Lite MCP server (stdio).
 * Env: RETRYSIGHT_URL (default http://127.0.0.1:18081), RETRYSIGHT_TOKEN (admin token)
 */
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'

const __dirname = dirname(fileURLToPath(import.meta.url))
const managerRoot = resolve(__dirname, '..')

function env(name: string, legacy?: string): string | undefined {
  const v = process.env[name]?.trim()
  if (v) return v
  if (legacy) return process.env[legacy]?.trim() || undefined
  return undefined
}

/** Resolve the admin token from RETRYSIGHT_TOKEN or the data-dir admin-token file. */
function resolveAdminToken(): string {
  const fromEnv = env('RETRYSIGHT_TOKEN', 'RETRYSITELITE_TOKEN')
  if (fromEnv) return fromEnv
  const dataDir = env('RETRYSIGHT_DATA_DIR', 'RETRYSITELITE_DATA_DIR') || join(managerRoot, 'data')
  const tokenFile = join(dataDir, 'admin-token')
  try {
    if (existsSync(tokenFile)) return readFileSync(tokenFile, 'utf8').trim()
  } catch {
    /* ignore */
  }
  return ''
}

const adminToken = resolveAdminToken()
const baseUrl = (env('RETRYSIGHT_URL', 'RETRYSITELITE_URL') || 'http://127.0.0.1:18081').replace(/\/$/, '')

async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${baseUrl}/graphql`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(adminToken ? { authorization: `Bearer ${adminToken}` } : {}),
    },
    body: JSON.stringify({ query, variables }),
  })
  const json = (await res.json()) as { data?: T; errors?: { message: string }[] }
  if (!res.ok || json.errors?.length) {
    throw new Error(json.errors?.map((e) => e.message).join('; ') || `HTTP ${res.status}`)
  }
  return json.data as T
}

const server = new McpServer({ name: 'retrysight-lite', version: '1.0.0' })

server.tool(
  'dashboard_summary',
  'Agentic AI dashboard: retries, sessions, LLMs, event breakdowns',
  {
    from: z.string().optional(),
    to: z.string().optional(),
    sourceTool: z.string().optional(),
    agentId: z.string().optional(),
    model: z.string().optional(),
  },
  async (vars) => {
    const data = await gql<{ dashboardSummary: unknown }>(
      `query($from: DateTime, $to: DateTime, $sourceTool: String, $agentId: ID, $model: String) {
        dashboardSummary(from: $from, to: $to, sourceTool: $sourceTool, agentId: $agentId, model: $model) {
          taskCount totalRetries retryRate completionRate abandonRate
          inputTokens outputTokens avgSessionMinutes
          sessionStarts sessionEnds subagentEvents compactionEvents
          byTool { sourceTool count retries }
          byEventType { eventType count }
          byModel { model inputTokens outputTokens events estimatedCostUsd }
          topRetryTasks { id title sourceTool retryCount status startedAt }
        }
      }`,
      vars,
    )
    return { content: [{ type: 'text', text: JSON.stringify(data.dashboardSummary, null, 2) }] }
  },
)

server.tool(
  'list_tasks',
  'List recent tasks with retry counts',
  {
    sourceTool: z.string().optional(),
    minRetries: z.number().int().optional(),
    size: z.number().int().optional(),
  },
  async ({ sourceTool, minRetries, size }) => {
    const data = await gql<{ tasks: unknown }>(
      `query($sourceTool: String, $minRetries: Int, $size: Int) {
        tasks(sourceTool: $sourceTool, minRetries: $minRetries, size: $size) {
          totalCount
          items { id title sourceTool status retryCount inputTokens outputTokens startedAt repoName }
        }
      }`,
      { sourceTool, minRetries, size: size ?? 20 },
    )
    return { content: [{ type: 'text', text: JSON.stringify(data.tasks, null, 2) }] }
  },
)

server.tool('task_detail', 'Task detail + chronological event timeline', { id: z.string() }, async ({ id }) => {
  const data = await gql<{ task: unknown }>(
    `query($id: ID!) {
      task(id: $id) {
        id title sourceTool status retryCount inputTokens outputTokens
        startedAt endedAt projectRoot repoName gitBranch
        timeline { eventType occurredAt summary isRetrySignal }
      }
    }`,
    { id },
  )
  return { content: [{ type: 'text', text: JSON.stringify(data.task, null, 2) }] }
})

server.tool('list_agents', 'List collector agents', {}, async () => {
  const data = await gql<{ agents: unknown[] }>(
    `query { agents { id name hostname developerEmail lastHeartbeatAt stale installedCollectors } }`,
  )
  return { content: [{ type: 'text', text: JSON.stringify(data.agents, null, 2) }] }
})

server.tool('collector_status', 'In-process collector runtime status', {}, async () => {
  const data = await gql<{ collectors: unknown }>(
    `query { collectors { enabled running agentId collectors lastPollAt lastFlushAt lastError } }`,
  )
  return { content: [{ type: 'text', text: JSON.stringify(data.collectors, null, 2) }] }
})

await server.connect(new StdioServerTransport())
