// SPDX-License-Identifier: Apache-2.0

import { readFileSync } from 'node:fs'
import Fastify, { type FastifyInstance } from 'fastify'
import rateLimit from '@fastify/rate-limit'
import { config } from './config.js'
import {
  extractAdminToken,
  assertAdminToken,
  isIngestPath,
  isPublicPath,
} from './auth.js'
import { cleanupOldData, getDb, generateRawKey, insertApiKey, nowIso } from './db.js'
import {
  assertAgentKey,
  batchRequestSchema,
  heartbeatSchema,
  processBatch,
  registerOrResolveAgent,
  listAgents,
  listTasks,
  getTask,
  listEvents,
  getAgent,
} from './ingest.js'
import { buildMcpConfig, createGraphqlYoga } from './graphql.js'
import { getAgenticDashboard, getTaskTimeline, type DashboardFilters } from './metrics.js'
import { getCollectorStatus, loadCollectorConfigs, sanitizeCollectorConfigMap, saveCollectorConfigs, type CollectorConfigMap } from './collectors/runtime.js'

export async function createServer(): Promise<FastifyInstance> {
  getDb()

  const fastifyOpts: Record<string, unknown> = {
    logger: process.env.RETRYSIGHT_LOG === '1',
    bodyLimit: config.bodyLimitBytes,
  }
  // Optional TLS/HTTPS
  if (config.tlsEnabled && config.tlsCertPath && config.tlsKeyPath) {
    fastifyOpts.https = {
      key: readFileSync(config.tlsKeyPath),
      cert: readFileSync(config.tlsCertPath),
    }
  }
  const app = Fastify(fastifyOpts)

  // Never leak internal error messages to clients (e.g. SQLite details).
  app.setErrorHandler((err, _req, reply) => {
    console.error('[retrysight-lite] Unhandled error:', err)
    const e = err as { statusCode?: number; message?: string }
    const status = e.statusCode && e.statusCode < 500 ? e.statusCode : 500
    reply
      .code(status)
      .send({ error: status >= 500 ? 'Internal server error' : e.message || 'Error' })
  })

  // Rate limiting: 100 req/min per IP on admin/ingest routes, 20 req/min on GraphQL
  try {
    await app.register(rateLimit, {
      global: false,
      max: 100,
      timeWindow: '1 minute',
      keyGenerator: (req) => req.ip,
    })
  } catch {
    /* plugin already registered */
  }

  // Schedule periodic data retention cleanup if configured
  let retentionTimer: ReturnType<typeof setInterval> | null = null
  if (config.retentionDays > 0) {
    cleanupOldData(config.retentionDays)
    retentionTimer = setInterval(() => cleanupOldData(config.retentionDays), config.retentionIntervalMs)
    retentionTimer.unref()
  }

  // CORS off for TUI/CLI. Allow loopback browser origins for the Flutter web dev UI.
  app.addHook('onRequest', async (req, reply) => {
    const origin = req.headers.origin
    if (origin && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(origin)) {
      reply.header('Access-Control-Allow-Origin', origin)
      reply.header('Vary', 'Origin')
      reply.header(
        'Access-Control-Allow-Headers',
        'Authorization, Content-Type, X-RetrySight-Admin-Token, X-Admin-Authenticated',
      )
      reply.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
    }
    if (req.method === 'OPTIONS') {
      return reply.code(204).send()
    }
  })

  // Security headers
  app.addHook('onResponse', async (_req, reply) => {
    reply
      .header('X-Content-Type-Options', 'nosniff')
      .header('X-Frame-Options', 'DENY')
      .header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'")
      .header('Referrer-Policy', 'no-referrer')
      .header('X-XSS-Protection', '0')
  })

  // DNS-rebinding / Host-header guard: when bound to loopback, only accept
  // requests addressed to 127.0.0.1 or localhost.
  app.addHook('onRequest', async (req, reply) => {
    if (config.host === '127.0.0.1' || config.host === 'localhost') {
      let host = (req.headers.host || '').trim().toLowerCase()
      if (host.startsWith('[')) {
        const end = host.indexOf(']')
        host = end >= 0 ? host.slice(0, end + 1) : host
      } else {
        host = host.split(':')[0]
      }
      const allowed =
        host === '' || host === '127.0.0.1' || host === 'localhost' || host === '[::1]'
      if (!allowed) {
        return reply.code(403).send({ error: 'Forbidden host' })
      }
    }
  })

  app.addHook('onRequest', async (req, reply) => {
    const pathname = (req.url.split('?')[0] || '/').replace(/\/+$/, '') || '/'
    if (isPublicPath(pathname) || isIngestPath(pathname)) return
    try {
      assertAdminToken(extractAdminToken(req.headers))
    } catch {
      return reply.code(401).send({ error: 'Unauthorized' })
    }
  })

  const yoga = createGraphqlYoga()
  app.route({
    method: ['GET', 'POST'],
    url: '/graphql',
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
    handler: async (req, reply) => {
      // Extract and validate admin token for GraphQL context
      const adminToken = extractAdminToken(req.headers)
      let adminAuthenticated = false
      try {
        assertAdminToken(adminToken)
        adminAuthenticated = true
      } catch {
        /* unauthenticated — context will restrict mutations */
      }

      const url = `http://${req.headers.host || 'localhost'}${req.url}`
      const headers = new Headers()
      for (const [key, value] of Object.entries(req.headers)) {
        if (value == null) continue
        if (Array.isArray(value)) value.forEach((v) => headers.append(key, v))
        else headers.set(key, value)
      }
      headers.set('x-admin-authenticated', adminAuthenticated ? '1' : '0')
      const hasBody = req.method !== 'GET' && req.method !== 'HEAD'
      const response = await yoga.fetch(url, {
        method: req.method,
        headers,
        body: hasBody ? JSON.stringify(req.body ?? {}) : undefined,
      })
      reply.status(response.status)
      response.headers.forEach((value, key) => {
        if (key.toLowerCase() === 'transfer-encoding') return
        reply.header(key, value)
      })
      return reply.send(Buffer.from(await response.arrayBuffer()))
    },
  })

  app.get('/api/v1/health', async () => ({
    status: 'ok',
    service: 'retrysight-lite',
    mode: 'standalone',
    collectors: getCollectorStatus().running,
  }))

  app.get('/api/v1/collectors', async () => getCollectorStatus())

  app.get('/api/v1/collectors/config', async () => loadCollectorConfigs())

  app.put('/api/v1/collectors/config', async (req, reply) => {
    const body = req.body as CollectorConfigMap | undefined
    if (!body || typeof body !== 'object') {
      return reply.code(400).send({ error: 'Invalid config body' })
    }
    // Depth-limit to prevent nested-object memory exhaustion
    function maxDepth(v: unknown, depth: number): number {
      if (depth > 16) return depth
      if (typeof v === 'object' && v !== null) {
        let d = depth
        for (const val of Object.values(v as Record<string, unknown>)) {
          d = Math.max(d, maxDepth(val, depth + 1))
          if (d > 16) break
        }
        return d
      }
      return depth
    }
    if (maxDepth(body, 1) > 16) {
      return reply.code(400).send({ error: 'Config body too deeply nested' })
    }
    const sanitized = sanitizeCollectorConfigMap(body)
    if (!sanitized) {
      return reply.code(400).send({ error: 'Invalid collector config: unknown tool or format' })
    }
    saveCollectorConfigs(sanitized)
    return { status: 'ok' }
  })

  app.get('/api/v1/dashboard', async (req) => {
    const q = req.query as DashboardFilters
    return getAgenticDashboard(q)
  })

  app.get('/api/v1/agents', async () => listAgents())

  app.get('/api/v1/agents/:id', async (req, reply) => {
    const { id } = req.params as { id: string }
    const agent = getAgent(id)
    if (!agent) return reply.code(404).send({ error: 'Not found' })
    return agent
  })

  app.get('/api/v1/tasks', async (req) => {
    const q = req.query as Record<string, string>
    return listTasks({
      agentId: q.agentId,
      sourceTool: q.sourceTool,
      from: q.from,
      to: q.to,
      minRetries: q.minRetries ? Number(q.minRetries) : undefined,
      page: q.page ? Number(q.page) : 0,
      size: q.size ? Number(q.size) : 50,
    })
  })

  app.get('/api/v1/tasks/:id', async (req, reply) => {
    const { id } = req.params as { id: string }
    const task = getTask(id)
    if (!task) return reply.code(404).send({ error: 'Not found' })
    return {
      ...task,
      events: listEvents(id),
      timeline: getTaskTimeline(id),
    }
  })

  app.get('/api/v1/mcp/config', async () => buildMcpConfig())

  app.post('/api/v1/api-keys', async (req, reply) => {
    const body = req.body as { name?: string }
    const name = (body.name || 'agent-key').slice(0, 64)
    if (!name.trim()) {
      return reply.code(400).send({ error: 'Name is required' })
    }
    const rawKey = generateRawKey()
    const created = insertApiKey(getDb(), name, rawKey, 'agent')
    return { id: created.id, keyPrefix: created.keyPrefix, rawKey, createdAt: nowIso() }
  })

  app.post('/api/v1/ingest/heartbeat', {
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    handler: async (req, reply) => {
    try {
      const keyHash = assertAgentKey(req.headers['x-agent-api-key'] as string | undefined)
      const heartbeat = heartbeatSchema.parse(req.body)
      const agentIdHeader = req.headers['x-agent-id'] as string | undefined
      const agent = registerOrResolveAgent(agentIdHeader, heartbeat, keyHash)
      processBatch(agent.id, { heartbeat, taskStarts: null, items: null })
      return { agentId: agent.id, status: 'ok' }
    } catch (err) {
      return sendError(reply, err)
    }
  }})

  app.post('/api/v1/ingest/batch', {
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    handler: async (req, reply) => {
    try {
      const keyHash = assertAgentKey(req.headers['x-agent-api-key'] as string | undefined)
      const body = batchRequestSchema.parse(req.body)
      const agentIdHeader = req.headers['x-agent-id'] as string | undefined
      const agent = registerOrResolveAgent(agentIdHeader, body.heartbeat, keyHash)
      const result = processBatch(agent.id, body)
      return { agentId: agent.id, ...result }
    } catch (err) {
      return sendError(reply, err)
    }
  }})

  return app
}

function sendError(reply: { code: (n: number) => { send: (b: unknown) => unknown } }, err: unknown) {
  const e = err as Error & { statusCode?: number; issues?: unknown }
  const status = e.statusCode || (e.name === 'ZodError' ? 400 : 500)
  if (status >= 500) {
    console.error('[retrysight-lite] Internal error:', e)
    return reply.code(500).send({ error: 'Internal server error' })
  }
  if (e.name === 'ZodError' && Array.isArray(e.issues)) {
    const first = e.issues[0] as { message?: string } | undefined
    return reply.code(400).send({ error: first?.message ? String(first.message) : 'Invalid request' })
  }
  return reply.code(status).send({ error: e.message || 'Error' })
}
