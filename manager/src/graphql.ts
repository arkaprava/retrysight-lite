// SPDX-License-Identifier: Apache-2.0

import { createSchema, createYoga } from 'graphql-yoga'
import { GraphQLError, NoSchemaIntrospectionCustomRule, type ValidationRule } from 'graphql'
import { config } from './config.js'
import {
  getAgent,
  getTask,
  listAgents,
  listEvents,
  listTasks,
} from './ingest.js'
import { getAgenticDashboard, getTaskTimeline } from './metrics.js'
import {
  generateRawKey,
  getDb,
  insertApiKey,
  nowIso,
} from './db.js'
import { getCollectorStatus } from './collectors/runtime.js'

const typeDefs = /* GraphQL */ `
  scalar DateTime

  type Query {
    health: String!
    collectors: CollectorStatus!
    agents: [Agent!]!
    agent(id: ID!): Agent
    tasks(
      agentId: ID
      sourceTool: String
      from: DateTime
      to: DateTime
      minRetries: Int
      page: Int
      size: Int
    ): TaskConnection!
    task(id: ID!): Task
    dashboardSummary(
      from: DateTime
      to: DateTime
      sourceTool: String
      agentId: ID
      model: String
    ): AgenticDashboard!
    apiKeys: [ApiKeySummary!]!
    mcpConfig: McpConfig!
  }

  type Mutation {
    createApiKey(name: String!): ApiKeyCreated!
    revokeApiKey(id: ID!): Boolean!
  }

  type CollectorStatus {
    enabled: Boolean!
    running: Boolean!
    agentId: ID
    collectors: [String!]!
    lastPollAt: DateTime
    lastFlushAt: DateTime
    lastError: String
  }

  type Agent {
    id: ID!
    name: String!
    developerEmail: String!
    osUsername: String
    displayName: String
    gitEmail: String
    hostname: String!
    lastHeartbeatAt: DateTime
    installedCollectors: String
    createdAt: DateTime!
    stale: Boolean!
  }

  type TaskConnection {
    items: [Task!]!
    totalCount: Int!
  }

  type Task {
    id: ID!
    agentId: ID!
    sourceTool: String!
    status: String!
    title: String
    retryCount: Int!
    inputTokens: Int!
    outputTokens: Int!
    startedAt: DateTime!
    endedAt: DateTime
    projectRoot: String
    repoName: String
    gitBranch: String
    gitCommit: String
    remoteUrl: String
    createdAt: DateTime!
    updatedAt: DateTime!
    events: [TaskEvent!]!
    timeline: [TimelineEvent!]!
    agent: Agent
  }

  type TaskEvent {
    id: ID!
    taskId: ID!
    eventType: String!
    payloadJson: String
    occurredAt: DateTime!
  }

  type TimelineEvent {
    id: ID!
    eventType: String!
    occurredAt: DateTime!
    summary: String!
    isRetrySignal: Boolean!
  }

  type AgenticDashboard {
    taskCount: Int!
    activeCount: Int!
    completedCount: Int!
    abandonedCount: Int!
    completionRate: Float!
    abandonRate: Float!
    totalRetries: Int!
    avgRetries: Float!
    retryRate: Float!
    inputTokens: Int!
    outputTokens: Int!
    agentCount: Int!
    avgSessionMinutes: Float!
    sessionStarts: Int!
    sessionEnds: Int!
    subagentEvents: Int!
    compactionEvents: Int!
    byTool: [ToolCount!]!
    byEventType: [EventTypeCount!]!
    byStatus: [StatusCount!]!
    byModel: [LlmModelStats!]!
    retryTrend: [TrendPoint!]!
    topRetryTasks: [TopRetryTask!]!
    availableTools: [String!]!
    availableModels: [String!]!
    availableAgents: [AvailableAgent!]!
    byAgent: [AgentSummary!]!
    byRepo: [RepoStat!]!
    durationDistribution: [DurationBucket!]!
    dailyCompletionRate: [DailyCompletion!]!
    hourlyActivity: [HourlyActivity!]!
    byModelRetryRate: [ModelRetryRate!]!
    agentHealth: [AgentHealth!]!
    estimatedCostUsd: Float!
    prevEstimatedCostUsd: Float!
    prevTaskCount: Int!
    prevTotalRetries: Int!
    prevActiveCount: Int!
    prevCompletedCount: Int!
    prevAbandonedCount: Int!
    prevInputTokens: Int!
    prevOutputTokens: Int!
    prevAvgRetries: Float!
    prevRetryRate: Float!
    prevAgentCount: Int!
    prevAvgSessionMinutes: Float!
    budgetUsd: Float
    budgetUsedFraction: Float
    periodComparisons: [PeriodComparison!]!
  }

  type PeriodTotals {
    taskCount: Int!
    totalRetries: Int!
    retryRate: Float!
    estimatedCostUsd: Float!
  }

  type PeriodComparison {
    label: String!
    current: PeriodTotals!
    previous: PeriodTotals!
  }

  type AvailableAgent {
    id: ID!
    name: String!
  }

  type AgentSummary {
    agentId: ID!
    agentName: String!
    taskCount: Int!
    retryCount: Int!
    inputTokens: Int!
    outputTokens: Int!
    avgDurationSec: Float!
  }

  type RepoStat {
    repoName: String!
    taskCount: Int!
    retryCount: Int!
    completedCount: Int!
    totalCount: Int!
    completionRate: Float!
  }

  type DurationBucket {
    bucket: String!
    count: Int!
  }

  type DailyCompletion {
    day: String!
    completed: Int!
    abandoned: Int!
    total: Int!
  }

  type HourlyActivity {
    hour: Int!
    count: Int!
  }

  type ModelRetryRate {
    model: String!
    totalTasks: Int!
    totalRetries: Int!
    retryRate: Float!
  }

  type AgentHealth {
    agentId: ID!
    agentName: String!
    lastHeartbeatAt: DateTime
    stale: Boolean!
    totalSessions: Int!
    activeTasks: Int!
  }

  type ToolCount {
    sourceTool: String!
    count: Int!
    retries: Int!
  }

  type EventTypeCount {
    eventType: String!
    count: Int!
  }

  type StatusCount {
    status: String!
    count: Int!
  }

  type LlmModelStats {
    model: String!
    inputTokens: Int!
    outputTokens: Int!
    events: Int!
    estimatedCostUsd: Float!
  }

  type TrendPoint {
    day: String!
    retries: Int!
    tasks: Int!
  }

  type TopRetryTask {
    id: ID!
    title: String
    sourceTool: String!
    retryCount: Int!
    status: String!
    startedAt: DateTime!
  }

  type ApiKeySummary {
    id: ID!
    name: String!
    keyPrefix: String!
    role: String!
    active: Boolean!
    createdAt: DateTime!
    lastUsedAt: DateTime
    revokedAt: DateTime
  }

  type ApiKeyCreated {
    key: ApiKeySummary!
    rawKey: String!
  }

  type McpConfig {
    transport: String!
    command: String!
    args: [String!]!
    env: [McpEnvVar!]!
    cursorJson: String!
    endpointHint: String!
  }

  type McpEnvVar {
    name: String!
    value: String!
    secret: Boolean!
  }
`

function mapAgent(row: ReturnType<typeof getAgent> | NonNullable<ReturnType<typeof listAgents>[number]>) {
  if (!row) return null
  const last = row.last_heartbeat_at ? Date.parse(row.last_heartbeat_at) : 0
  const stale = !last || Date.now() - last > config.staleAgentSeconds * 1000
  return {
    id: row.id,
    name: row.name,
    developerEmail: row.developer_email,
    osUsername: row.os_username,
    displayName: row.display_name,
    gitEmail: row.git_email,
    hostname: row.hostname,
    lastHeartbeatAt: row.last_heartbeat_at,
    installedCollectors: row.installed_collectors,
    createdAt: row.created_at,
    stale,
  }
}

function mapTask(row: NonNullable<ReturnType<typeof getTask>>) {
  return {
    id: row.id,
    agentId: row.agent_id,
    sourceTool: row.source_tool,
    status: row.status,
    title: row.title,
    retryCount: row.retry_count,
    inputTokens: row.input_tokens,
    outputTokens: row.output_tokens,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    projectRoot: row.project_root,
    repoName: row.repo_name,
    gitBranch: row.git_branch,
    gitCommit: row.git_commit,
    remoteUrl: row.remote_url,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function buildMcpConfig() {
  const managerRoot = process.cwd()
  const env = [
    { name: 'RETRYSIGHT_URL', value: config.publicUrl, secret: false },
  ]
  const configJson = JSON.stringify(
    {
      mcpServers: {
        'retrysight-lite': {
          command: 'npm',
          args: ['run', 'mcp', '--prefix', managerRoot],
          env: {
            RETRYSIGHT_URL: config.publicUrl,
          },
        },
      },
    },
    null,
    2,
  )
  return {
    transport: 'stdio',
    command: 'npm',
    args: ['run', 'mcp', '--prefix', managerRoot],
    env,
    configJson,
    endpointHint: `${config.publicUrl}/graphql`,
  }
}

export type GraphqlContext = {
  adminAuthenticated: boolean
}

function requireAdmin(context: GraphqlContext): void {
  if (!context.adminAuthenticated) {
    throw new Error('Unauthorized - admin token required')
  }
}

const resolvers = {
  Query: {
    health: () => 'ok',
    collectors: (_: unknown, __: unknown, context: GraphqlContext) => {
      requireAdmin(context)
      const s = getCollectorStatus()
      return {
        enabled: s.enabled,
        running: s.running,
        agentId: s.agentId,
        collectors: s.collectors,
        lastPollAt: s.lastPollAt,
        lastFlushAt: s.lastFlushAt,
        lastError: s.lastError,
      }
    },
    agents: (_: unknown, __: unknown, context: GraphqlContext) => {
      requireAdmin(context)
      return listAgents().map(mapAgent)
    },
    agent: (_: unknown, args: { id: string }, context: GraphqlContext) => {
      requireAdmin(context)
      return mapAgent(getAgent(args.id))
    },
    tasks: (_: unknown, args: Record<string, unknown>, context: GraphqlContext) => {
      requireAdmin(context)
      const result = listTasks({
        agentId: args.agentId as string | undefined,
        sourceTool: args.sourceTool as string | undefined,
        from: args.from as string | undefined,
        to: args.to as string | undefined,
        minRetries: args.minRetries as number | undefined,
        page: args.page as number | undefined,
        size: args.size as number | undefined,
      })
      return { items: result.items.map(mapTask), totalCount: result.totalCount }
    },
    task: (_: unknown, args: { id: string }, context: GraphqlContext) => {
      requireAdmin(context)
      const row = getTask(args.id)
      return row ? mapTask(row) : null
    },
    dashboardSummary: (
      _: unknown,
      args: { from?: string; to?: string; sourceTool?: string; agentId?: string; model?: string },
      context: GraphqlContext,
    ) => {
      requireAdmin(context)
      return getAgenticDashboard(args)
    },
    apiKeys: (_: unknown, __: unknown, context: GraphqlContext) => {
      requireAdmin(context)
      const rows = getDb()
        .prepare(
          `SELECT id, name, key_prefix, role, active, created_at, last_used_at, revoked_at
           FROM api_keys ORDER BY created_at DESC`,
        )
        .all() as Array<{
        id: string
        name: string
        key_prefix: string
        role: string
        active: number
        created_at: string
        last_used_at: string | null
        revoked_at: string | null
      }>
      return rows.map((r) => ({
        id: r.id,
        name: r.name,
        keyPrefix: r.key_prefix,
        role: r.role,
        active: !!r.active,
        createdAt: r.created_at,
        lastUsedAt: r.last_used_at,
        revokedAt: r.revoked_at,
      }))
    },
    mcpConfig: (_: unknown, __: unknown, context: GraphqlContext) => {
      requireAdmin(context)
      return buildMcpConfig()
    },
  },
  Mutation: {
    createApiKey: (_: unknown, args: { name: string }, context: GraphqlContext) => {
      requireAdmin(context)
      const name = args.name.slice(0, 64)
      if (!name.trim()) throw new Error('Name is required')
      const rawKey = generateRawKey()
      const created = insertApiKey(getDb(), name, rawKey, 'agent')
      return {
        rawKey,
        key: {
          id: created.id,
          name,
          keyPrefix: created.keyPrefix,
          role: 'agent',
          active: true,
          createdAt: nowIso(),
          lastUsedAt: null,
          revokedAt: null,
        },
      }
    },
    revokeApiKey: (_: unknown, args: { id: string }, context: GraphqlContext) => {
      requireAdmin(context)
      getDb()
        .prepare('UPDATE api_keys SET active = 0, revoked_at = ? WHERE id = ?')
        .run(nowIso(), args.id)
      return true
    },
  },
  Task: {
    events: (parent: { id: string }) =>
      listEvents(parent.id).map((e) => {
        const row = e as {
          id: string
          task_id: string
          event_type: string
          payload_json: string | null
          occurred_at: string
        }
        return {
          id: row.id,
          taskId: row.task_id,
          eventType: row.event_type,
          payloadJson: row.payload_json,
          occurredAt: row.occurred_at,
        }
      }),
    timeline: (parent: { id: string }) => getTaskTimeline(parent.id),
    agent: (parent: { agentId: string }) => mapAgent(getAgent(parent.agentId)),
  },
}

/** Cap the total number of selected fields in a single GraphQL document.
 *  Without this, a client can bypass the 20 req/min rate limit's intent by
 *  aliasing the same expensive field hundreds of times in one request
 *  (e.g. `a: tasks(size: 200) { ... } b: tasks(size: 200) { ... } ...`). */
const MAX_QUERY_FIELDS = 750

function createFieldCountRule(): ValidationRule {
  return (context) => {
    let count = 0
    return {
      Field() {
        count += 1
        if (count > MAX_QUERY_FIELDS) {
          context.reportError(
            new GraphQLError(`Query exceeds maximum allowed field count (${MAX_QUERY_FIELDS})`),
          )
        }
      },
    }
  }
}

export function createGraphqlYoga() {
  const schema = createSchema({ typeDefs, resolvers })
  return createYoga({
    schema,
    context: async ({ request }: { request: Request }): Promise<GraphqlContext> => ({
      adminAuthenticated: request.headers.get('x-admin-authenticated') === '1',
    }),
    graphqlEndpoint: '/graphql',
    landingPage: config.graphqlDev,
    graphiql: config.graphqlDev,
    plugins: [
      {
        onValidate({ addValidationRule }: { addValidationRule: (rule: ValidationRule) => void }) {
          addValidationRule(createFieldCountRule())
          if (!config.graphqlDev) addValidationRule(NoSchemaIntrospectionCustomRule)
        },
      },
    ] as never[],
  })
}

export { buildMcpConfig }
