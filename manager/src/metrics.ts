// SPDX-License-Identifier: Apache-2.0

import { config } from './config.js'
import { getDb } from './db.js'

export type DashboardFilters = {
  from?: string
  to?: string
  sourceTool?: string
  agentId?: string
  model?: string
}

export type LlmModelStats = {
  model: string
  inputTokens: number
  outputTokens: number
  events: number
  estimatedCostUsd: number
}

export type AgenticDashboard = {
  filters: DashboardFilters
  taskCount: number
  activeCount: number
  completedCount: number
  abandonedCount: number
  completionRate: number
  abandonRate: number
  totalRetries: number
  avgRetries: number
  retryRate: number
  inputTokens: number
  outputTokens: number
  agentCount: number
  avgSessionMinutes: number
  sessionStarts: number
  sessionEnds: number
  subagentEvents: number
  compactionEvents: number
  byTool: { sourceTool: string; count: number; retries: number }[]
  byEventType: { eventType: string; count: number }[]
  byStatus: { status: string; count: number }[]
  byModel: LlmModelStats[]
  retryTrend: { day: string; retries: number; tasks: number }[]
  topRetryTasks: {
    id: string
    title: string | null
    sourceTool: string
    retryCount: number
    status: string
    startedAt: string
  }[]
  availableTools: string[]
  availableModels: string[]
  availableAgents: { id: string; name: string }[]
  byAgent: {
    agentId: string
    agentName: string
    taskCount: number
    retryCount: number
    inputTokens: number
    outputTokens: number
    avgDurationSec: number
  }[]
  byRepo: {
    repoName: string
    taskCount: number
    retryCount: number
    completedCount: number
    totalCount: number
    completionRate: number
  }[]
  durationDistribution: {
    bucket: string
    count: number
  }[]
  dailyCompletionRate: {
    day: string
    completed: number
    abandoned: number
    total: number
  }[]
  hourlyActivity: {
    hour: number
    count: number
  }[]
  byModelRetryRate: {
    model: string
    totalTasks: number
    totalRetries: number
    retryRate: number
  }[]
  agentHealth: {
    agentId: string
    agentName: string
    lastHeartbeatAt: string | null
    stale: boolean
    totalSessions: number
    activeTasks: number
  }[]
  prevTaskCount: number
  prevTotalRetries: number
  prevActiveCount: number
  prevCompletedCount: number
  prevAbandonedCount: number
  prevInputTokens: number
  prevOutputTokens: number
  prevAvgRetries: number
  prevRetryRate: number
  prevAgentCount: number
  prevAvgSessionMinutes: number
  estimatedCostUsd: number
  prevEstimatedCostUsd: number
}

/**
 * Rough $/1M token pricing for display — not billing truth.
 * Based on published API pricing where available; $0 for local/open models.
 */
const MODEL_RATES: Record<string, { inPerM: number; outPerM: number }> = {
  // ─── Default fallback ───
  default: { inPerM: 3, outPerM: 15 },

  // ─── OpenAI ───
  'gpt-4o': { inPerM: 2.5, outPerM: 10 },
  'gpt-4o-mini': { inPerM: 0.15, outPerM: 0.6 },
  'gpt-4.1': { inPerM: 2, outPerM: 8 },
  'gpt-4.1-mini': { inPerM: 0.4, outPerM: 1.6 },
  'gpt-4.1-nano': { inPerM: 0.1, outPerM: 0.4 },
  'gpt-4-turbo': { inPerM: 10, outPerM: 30 },
  'gpt-4': { inPerM: 30, outPerM: 60 },
  'gpt-3.5-turbo': { inPerM: 0.5, outPerM: 1.5 },
  'gpt-5-nano': { inPerM: 0.05, outPerM: 0.4 },
  'gpt-5-mini': { inPerM: 0.25, outPerM: 2 },
  'gpt-5': { inPerM: 1.25, outPerM: 10 },
  'gpt-5.1': { inPerM: 1.25, outPerM: 10 },
  'gpt-5.2': { inPerM: 1.75, outPerM: 14 },
  'gpt-5.4': { inPerM: 2.5, outPerM: 15 },
  'gpt-5.4-mini': { inPerM: 0.75, outPerM: 4.5 },
  'gpt-5.4-nano': { inPerM: 0.2, outPerM: 1.25 },
  'gpt-5.5': { inPerM: 5, outPerM: 30 },
  'gpt-5.6-luna': { inPerM: 1, outPerM: 6 },
  'gpt-5.6-terra': { inPerM: 2.5, outPerM: 15 },
  'gpt-5.6-sol': { inPerM: 5, outPerM: 30 },
  'o1': { inPerM: 15, outPerM: 60 },
  'o1-mini': { inPerM: 1.1, outPerM: 4.4 },
  'o1-preview': { inPerM: 15, outPerM: 60 },
  'o3': { inPerM: 2, outPerM: 8 },
  'o3-mini': { inPerM: 1.1, outPerM: 4.4 },
  'o4-mini': { inPerM: 1.1, outPerM: 4.4 },

  // ─── Anthropic / Claude ───
  'claude-3-5-haiku': { inPerM: 0.8, outPerM: 4 },
  'claude-3-5-sonnet': { inPerM: 3, outPerM: 15 },
  'claude-3-7-sonnet': { inPerM: 3, outPerM: 15 },
  'claude-3-haiku': { inPerM: 0.25, outPerM: 1.25 },
  'claude-3-opus': { inPerM: 15, outPerM: 75 },
  'claude-sonnet-4': { inPerM: 3, outPerM: 15 },
  'claude-4-sonnet': { inPerM: 3, outPerM: 15 },
  'claude-4.5-sonnet': { inPerM: 3, outPerM: 15 },
  'claude-4.5-haiku': { inPerM: 1, outPerM: 5 },
  'claude-4.5-opus': { inPerM: 5, outPerM: 25 },
  'claude-4.6-opus': { inPerM: 5, outPerM: 25 },
  'claude-4.7-opus': { inPerM: 5, outPerM: 25 },
  'claude-4.8-opus': { inPerM: 5, outPerM: 25 },
  'claude-4-opus': { inPerM: 5, outPerM: 25 },
  'claude-haiku-4-5': { inPerM: 1, outPerM: 5 },
  'claude-sonnet-5': { inPerM: 3, outPerM: 15 },
  'claude-5-sonnet': { inPerM: 3, outPerM: 15 },
  'claude-opus-5': { inPerM: 5, outPerM: 25 },
  'claude-5-opus': { inPerM: 5, outPerM: 25 },
  'claude-fable-5': { inPerM: 10, outPerM: 50 },
  'claude-5-fable': { inPerM: 10, outPerM: 50 },
  'claude-opus': { inPerM: 5, outPerM: 25 },

  // ─── Google Gemini ───
  'gemini-1.5-pro': { inPerM: 1.25, outPerM: 5 },
  'gemini-1.5-flash': { inPerM: 0.075, outPerM: 0.3 },
  'gemini-2.0-flash': { inPerM: 0.1, outPerM: 0.4 },
  'gemini-2.0-flash-lite': { inPerM: 0.075, outPerM: 0.3 },
  'gemini-2.5-pro': { inPerM: 1.25, outPerM: 10 },
  'gemini-2.5-flash': { inPerM: 0.3, outPerM: 2.5 },
  'gemini-2.5-flash-lite': { inPerM: 0.1, outPerM: 0.4 },
  'gemini-3-flash': { inPerM: 0.5, outPerM: 3 },
  'gemini-3.1-pro': { inPerM: 2, outPerM: 12 },
  'gemini-3.1-flash-lite': { inPerM: 0.25, outPerM: 1.5 },
  'gemini-3.5-flash': { inPerM: 1.5, outPerM: 9 },
  'gemini-3.5-flash-lite': { inPerM: 0.3, outPerM: 2.5 },
  'gemini-3.6-flash': { inPerM: 1.5, outPerM: 7.5 },
  'gemini': { inPerM: 2, outPerM: 12 },

  // ─── Meta Llama ───
  'llama-3.1-8b': { inPerM: 0.05, outPerM: 0.25 },
  'llama-3.1-70b': { inPerM: 0.35, outPerM: 0.4 },
  'llama-3.1-405b': { inPerM: 2.5, outPerM: 2.5 },
  'llama-3.2-3b': { inPerM: 0.03, outPerM: 0.15 },
  'llama-3.2-11b': { inPerM: 0.05, outPerM: 0.25 },
  'llama-3.2-90b': { inPerM: 0.35, outPerM: 0.4 },
  'llama-3.3-70b': { inPerM: 0.35, outPerM: 0.4 },
  'llama-4': { inPerM: 0.35, outPerM: 0.4 },
  'llama': { inPerM: 0.3, outPerM: 0.35 },

  // ─── Mistral ───
  'mistral-large': { inPerM: 2, outPerM: 6 },
  'mistral-small': { inPerM: 0.2, outPerM: 0.6 },
  'mistral-medium': { inPerM: 0.35, outPerM: 1.1 },
  'codestral': { inPerM: 0.25, outPerM: 1 },
  'ministral-3b': { inPerM: 0.04, outPerM: 0.2 },
  'ministral-8b': { inPerM: 0.1, outPerM: 0.5 },
  'mistral': { inPerM: 0.5, outPerM: 1.5 },

  // ─── DeepSeek ───
  'deepseek-v2': { inPerM: 0.14, outPerM: 0.28 },
  'deepseek-v3': { inPerM: 0.27, outPerM: 1.1 },
  'deepseek-r1': { inPerM: 0.55, outPerM: 2.19 },
  'deepseek-v4-flash': { inPerM: 0.14, outPerM: 0.28 },
  'deepseek-v4-pro': { inPerM: 0.435, outPerM: 0.87 },
  'deepseek-v4': { inPerM: 0.435, outPerM: 0.87 },
  'deepseek': { inPerM: 0.14, outPerM: 0.28 },

  // ─── Qwen ───
  'qwen-2.5-7b': { inPerM: 0.1, outPerM: 0.4 },
  'qwen-2.5-32b': { inPerM: 0.18, outPerM: 0.72 },
  'qwen-2.5-72b': { inPerM: 0.35, outPerM: 0.75 },
  'qwen-3': { inPerM: 0.3, outPerM: 0.8 },
  'qwen-3.6': { inPerM: 0.25, outPerM: 0.75 },
  'qwen': { inPerM: 0.3, outPerM: 0.8 },

  // ─── xAI / Grok ───
  'grok-1': { inPerM: 5, outPerM: 15 },
  'grok-2': { inPerM: 2, outPerM: 10 },
  'grok-3': { inPerM: 3, outPerM: 15 },
  'grok-4': { inPerM: 3, outPerM: 15 },
  'grok-4-3': { inPerM: 1.25, outPerM: 2.5 },
  'grok-4-5': { inPerM: 1.25, outPerM: 2.5 },
  'grok': { inPerM: 3, outPerM: 15 },

  // ─── Cohere ───
  'command-r': { inPerM: 0.5, outPerM: 1.5 },
  'command-r-plus': { inPerM: 2.5, outPerM: 10 },
  'command': { inPerM: 0.5, outPerM: 1.5 },

  // ─── AI21 / Jamba ───
  'jamba-1.5': { inPerM: 0.2, outPerM: 0.8 },
  'jamba': { inPerM: 0.3, outPerM: 1.0 },

  // ─── Reka ───
  'reka-core': { inPerM: 0.4, outPerM: 1.5 },
  'reka-edge': { inPerM: 0.1, outPerM: 0.5 },
  'reka-flash': { inPerM: 0.2, outPerM: 0.8 },

  // ─── Databricks / DBRX ───
  'dbrx': { inPerM: 0.25, outPerM: 1.0 },
  'mixtral-8x7b': { inPerM: 0.1, outPerM: 0.4 },
  'mixtral-8x22b': { inPerM: 0.25, outPerM: 1.0 },

  // ─── Amazon ───
  'amazon-nova-pro': { inPerM: 0.8, outPerM: 3.2 },
  'amazon-nova-lite': { inPerM: 0.06, outPerM: 0.24 },
  'amazon-nova': { inPerM: 0.2, outPerM: 0.8 },

  // ─── Hosted open / inference providers ───
  'together': { inPerM: 0.1, outPerM: 0.5 },
  'fireworks': { inPerM: 0.1, outPerM: 0.5 },
  'groq': { inPerM: 0.1, outPerM: 0.4 },
  'perplexity': { inPerM: 0.2, outPerM: 0.8 },
  'anthropic': { inPerM: 3, outPerM: 15 },
  'openai': { inPerM: 2.5, outPerM: 10 },

  // ─── Local / self-hosted (zero cost, measurable usage) ───
  'ollama': { inPerM: 0, outPerM: 0 },
  'lm-studio': { inPerM: 0, outPerM: 0 },
  'lmstudio': { inPerM: 0, outPerM: 0 },
  'llamafile': { inPerM: 0, outPerM: 0 },
  'localai': { inPerM: 0, outPerM: 0 },
  'vllm': { inPerM: 0, outPerM: 0 },
  'tabby': { inPerM: 0, outPerM: 0 },
  'local': { inPerM: 0, outPerM: 0 },
}

/**
 * Priority-ordered alias prefixes for fuzzy matching.
 * Match against the *end* of the model string for sub-model granularity
 * (e.g. "deepseek-v4" matches before generic "deepseek").
 */
const MODEL_ALIASES: { prefix: string; key: string }[] = [
  // Longer prefixes first for most-specific match
  { prefix: 'gpt-4.1-nano', key: 'gpt-4.1-nano' },
  { prefix: 'gpt-4.1-mini', key: 'gpt-4.1-mini' },
  { prefix: 'gpt-4.1', key: 'gpt-4.1' },
  { prefix: 'gpt-4o-mini', key: 'gpt-4o-mini' },
  { prefix: 'gpt-4o', key: 'gpt-4o' },
  { prefix: 'gpt-4-turbo', key: 'gpt-4-turbo' },
  { prefix: 'gpt-3.5-turbo', key: 'gpt-3.5-turbo' },
  { prefix: 'gpt-5.6-sol', key: 'gpt-5.6-sol' },
  { prefix: 'gpt-5.6-terra', key: 'gpt-5.6-terra' },
  { prefix: 'gpt-5.6-luna', key: 'gpt-5.6-luna' },
  { prefix: 'gpt-5.5', key: 'gpt-5.5' },
  { prefix: 'gpt-5.4-nano', key: 'gpt-5.4-nano' },
  { prefix: 'gpt-5.4-mini', key: 'gpt-5.4-mini' },
  { prefix: 'gpt-5.4', key: 'gpt-5.4' },
  { prefix: 'gpt-5.2', key: 'gpt-5.2' },
  { prefix: 'gpt-5.1', key: 'gpt-5.1' },
  { prefix: 'gpt-5-nano', key: 'gpt-5-nano' },
  { prefix: 'gpt-5-mini', key: 'gpt-5-mini' },
  { prefix: 'gpt-5', key: 'gpt-5' },
  { prefix: 'o4-mini', key: 'o4-mini' },
  { prefix: 'o3-mini', key: 'o3-mini' },
  { prefix: 'o1-mini', key: 'o1-mini' },
  { prefix: 'o1-preview', key: 'o1-preview' },
  { prefix: 'o1', key: 'o1' },
  { prefix: 'o3', key: 'o3' },
  { prefix: 'claude-fable-5', key: 'claude-fable-5' },
  { prefix: 'claude-5-fable', key: 'claude-5-fable' },
  { prefix: 'claude-opus-5', key: 'claude-opus-5' },
  { prefix: 'claude-5-opus', key: 'claude-5-opus' },
  { prefix: 'claude-sonnet-5', key: 'claude-sonnet-5' },
  { prefix: 'claude-5-sonnet', key: 'claude-5-sonnet' },
  { prefix: 'claude-haiku-4-5', key: 'claude-haiku-4-5' },
  { prefix: 'claude-4.8-opus', key: 'claude-4.8-opus' },
  { prefix: 'claude-4.7-opus', key: 'claude-4.7-opus' },
  { prefix: 'claude-4.6-opus', key: 'claude-4.6-opus' },
  { prefix: 'claude-4.5-opus', key: 'claude-4.5-opus' },
  { prefix: 'claude-4.5-sonnet', key: 'claude-4.5-sonnet' },
  { prefix: 'claude-4.5-haiku', key: 'claude-4.5-haiku' },
  { prefix: 'claude-4-opus', key: 'claude-4-opus' },
  { prefix: 'claude-4-sonnet', key: 'claude-4-sonnet' },
  { prefix: 'claude-sonnet-4', key: 'claude-sonnet-4' },
  { prefix: 'claude-3.7-sonnet', key: 'claude-3.7-sonnet' },
  { prefix: 'claude-3.5-sonnet', key: 'claude-3.5-sonnet' },
  { prefix: 'claude-3.5-haiku', key: 'claude-3.5-haiku' },
  { prefix: 'claude-3-haiku', key: 'claude-3-haiku' },
  { prefix: 'claude-3-opus', key: 'claude-3-opus' },
  { prefix: 'claude-opus', key: 'claude-opus' },
  { prefix: 'gemini-3.6-flash', key: 'gemini-3.6-flash' },
  { prefix: 'gemini-3.5-flash-lite', key: 'gemini-3.5-flash-lite' },
  { prefix: 'gemini-3.5-flash', key: 'gemini-3.5-flash' },
  { prefix: 'gemini-3.1-flash-lite', key: 'gemini-3.1-flash-lite' },
  { prefix: 'gemini-3.1-pro', key: 'gemini-3.1-pro' },
  { prefix: 'gemini-3-flash', key: 'gemini-3-flash' },
  { prefix: 'gemini-2.5-flash-lite', key: 'gemini-2.5-flash-lite' },
  { prefix: 'gemini-2.5-flash', key: 'gemini-2.5-flash' },
  { prefix: 'gemini-2.5-pro', key: 'gemini-2.5-pro' },
  { prefix: 'gemini-2.0-flash-lite', key: 'gemini-2.0-flash-lite' },
  { prefix: 'gemini-2.0-flash', key: 'gemini-2.0-flash' },
  { prefix: 'gemini-1.5-flash', key: 'gemini-1.5-flash' },
  { prefix: 'gemini-1.5-pro', key: 'gemini-1.5-pro' },
  { prefix: 'deepseek-v4-pro', key: 'deepseek-v4-pro' },
  { prefix: 'deepseek-v4-flash', key: 'deepseek-v4-flash' },
  { prefix: 'deepseek-v4', key: 'deepseek-v4' },
  { prefix: 'deepseek-r1', key: 'deepseek-r1' },
  { prefix: 'deepseek-v3', key: 'deepseek-v3' },
  { prefix: 'deepseek-v2', key: 'deepseek-v2' },
  { prefix: 'llama-4', key: 'llama-4' },
  { prefix: 'llama-3.3-70b', key: 'llama-3.3-70b' },
  { prefix: 'llama-3.2-90b', key: 'llama-3.2-90b' },
  { prefix: 'llama-3.2-11b', key: 'llama-3.2-11b' },
  { prefix: 'llama-3.2-3b', key: 'llama-3.2-3b' },
  { prefix: 'llama-3.1-405b', key: 'llama-3.1-405b' },
  { prefix: 'llama-3.1-70b', key: 'llama-3.1-70b' },
  { prefix: 'llama-3.1-8b', key: 'llama-3.1-8b' },
  { prefix: 'mistral-large', key: 'mistral-large' },
  { prefix: 'mistral-small', key: 'mistral-small' },
  { prefix: 'mistral-medium', key: 'mistral-medium' },
  { prefix: 'ministral-8b', key: 'ministral-8b' },
  { prefix: 'ministral-3b', key: 'ministral-3b' },
  { prefix: 'qwen-3.6', key: 'qwen-3.6' },
  { prefix: 'qwen-2.5-72b', key: 'qwen-2.5-72b' },
  { prefix: 'qwen-2.5-32b', key: 'qwen-2.5-32b' },
  { prefix: 'qwen-2.5-7b', key: 'qwen-2.5-7b' },
  { prefix: 'grok-4-5', key: 'grok-4-5' },
  { prefix: 'grok-4-3', key: 'grok-4-3' },
  { prefix: 'grok-4', key: 'grok-4' },
  { prefix: 'grok-3', key: 'grok-3' },
  { prefix: 'grok-2', key: 'grok-2' },
  { prefix: 'grok-1', key: 'grok-1' },
  { prefix: 'command-r-plus', key: 'command-r-plus' },
  { prefix: 'command-r', key: 'command-r' },
  { prefix: 'jamba-1.5', key: 'jamba-1.5' },
  { prefix: 'reka-core', key: 'reka-core' },
  { prefix: 'reka-edge', key: 'reka-edge' },
  { prefix: 'reka-flash', key: 'reka-flash' },
  { prefix: 'mixtral-8x22b', key: 'mixtral-8x22b' },
  { prefix: 'mixtral-8x7b', key: 'mixtral-8x7b' },
  { prefix: 'amazon-nova-pro', key: 'amazon-nova-pro' },
  { prefix: 'amazon-nova-lite', key: 'amazon-nova-lite' },
  { prefix: 'lm-studio', key: 'lm-studio' },
  { prefix: 'lmstudio', key: 'lmstudio' },
]

function rateFor(model: string): { inPerM: number; outPerM: number } {
  const lower = model.toLowerCase()
  // Try exact match first
  if (MODEL_RATES[lower]) return MODEL_RATES[lower]
  // Try alias prefix matching (longest prefix wins)
  for (const alias of MODEL_ALIASES) {
    if (lower.includes(alias.prefix)) return MODEL_RATES[alias.key]
  }
  // Generic fallback by provider
  if (lower.includes('gpt') || lower.includes('openai')) return MODEL_RATES['openai']
  if (lower.includes('claude') || lower.includes('anthropic')) return MODEL_RATES['anthropic']
  if (lower.includes('gemini')) return MODEL_RATES['gemini']
  if (lower.includes('llama')) return MODEL_RATES['llama']
  if (lower.includes('mistral')) return MODEL_RATES['mistral']
  if (lower.includes('deepseek')) return MODEL_RATES['deepseek']
  if (lower.includes('qwen')) return MODEL_RATES['qwen']
  if (lower.includes('grok')) return MODEL_RATES['grok']
  if (lower.includes('command')) return MODEL_RATES['command']
  if (lower.includes('dbrx') || lower.includes('mixtral')) return MODEL_RATES['dbrx']
  if (lower.includes('jamba')) return MODEL_RATES['jamba']
  if (lower.includes('amazon') || lower.includes('nova')) return MODEL_RATES['amazon-nova']
  if (lower.includes('ollama') || lower.includes('local')) return MODEL_RATES['local']
  return MODEL_RATES['default']
}

function taskWhere(filters: DashboardFilters): { sql: string; params: Array<string | number> } {
  const clauses: string[] = []
  const params: Array<string | number> = []
  if (filters.from) {
    clauses.push('t.started_at >= ?')
    params.push(filters.from)
  }
  if (filters.to) {
    clauses.push('t.started_at <= ?')
    params.push(filters.to)
  }
  if (filters.sourceTool) {
    clauses.push('t.source_tool = ?')
    params.push(filters.sourceTool)
  }
  if (filters.agentId) {
    clauses.push('t.agent_id = ?')
    params.push(filters.agentId)
  }
  if (filters.model) {
    clauses.push(`EXISTS (
      SELECT 1 FROM task_events e
      WHERE e.task_id = t.id AND e.event_type = 'TOKEN_USAGE'
        AND instr(lower(coalesce(e.payload_json, '')), lower(?)) > 0
    )`)
    params.push(filters.model)
  }
  return {
    sql: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '',
    params,
  }
}

function aggregateModelStats(
  db: ReturnType<typeof getDb>,
  where: string,
  params: Array<string | number>,
  modelFilter?: string,
): LlmModelStats[] {
  const tokenRows = db
    .prepare(
      `SELECT e.payload_json AS payload
       FROM task_events e
       INNER JOIN tasks t ON t.id = e.task_id
       ${where ? `${where} AND` : 'WHERE'} e.event_type = 'TOKEN_USAGE'`,
    )
    .all(...params) as { payload: string | null }[]

  const modelMap = new Map<string, LlmModelStats>()
  for (const row of tokenRows) {
    let model = 'unknown'
    let input = 0
    let output = 0
    try {
      const p = row.payload ? JSON.parse(row.payload) : {}
      model = String(p.model || 'unknown')
      input = Number(p.inputTokens || 0)
      output = Number(p.outputTokens || 0)
    } catch {
      /* ignore */
    }
    if (modelFilter && !model.toLowerCase().includes(modelFilter.toLowerCase())) continue
    const cur = modelMap.get(model) || {
      model,
      inputTokens: 0,
      outputTokens: 0,
      events: 0,
      estimatedCostUsd: 0,
    }
    cur.inputTokens += input
    cur.outputTokens += output
    cur.events += 1
    modelMap.set(model, cur)
  }

  return [...modelMap.values()]
    .map((m) => {
      const rate = rateFor(m.model)
      m.estimatedCostUsd =
        (m.inputTokens / 1_000_000) * rate.inPerM + (m.outputTokens / 1_000_000) * rate.outPerM
      return m
    })
    .sort((a, b) => b.inputTokens + b.outputTokens - (a.inputTokens + a.outputTokens))
}

function totalEstimatedCost(models: LlmModelStats[]): number {
  return models.reduce((sum, m) => sum + m.estimatedCostUsd, 0)
}

export function getAgenticDashboard(filters: DashboardFilters = {}): AgenticDashboard {
  const db = getDb()
  const { sql: where, params } = taskWhere(filters)

  const totals = db
    .prepare(
      `SELECT
        COUNT(*) AS taskCount,
        COALESCE(SUM(CASE WHEN t.status = 'ACTIVE' THEN 1 ELSE 0 END), 0) AS activeCount,
        COALESCE(SUM(CASE WHEN t.status = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS completedCount,
        COALESCE(SUM(CASE WHEN t.status = 'ABANDONED' THEN 1 ELSE 0 END), 0) AS abandonedCount,
        COALESCE(SUM(t.retry_count), 0) AS totalRetries,
        COALESCE(AVG(t.retry_count), 0) AS avgRetries,
        COALESCE(SUM(CASE WHEN t.retry_count > 0 THEN 1 ELSE 0 END), 0) AS tasksWithRetries,
        COALESCE(SUM(t.input_tokens), 0) AS inputTokens,
        COALESCE(SUM(t.output_tokens), 0) AS outputTokens,
        COALESCE(AVG(
          CASE WHEN t.ended_at IS NOT NULL
            THEN (julianday(t.ended_at) - julianday(t.started_at)) * 24 * 60
            ELSE NULL END
        ), 0) AS avgSessionMinutes
       FROM tasks t ${where}`,
    )
    .get(...params) as {
    taskCount: number
    activeCount: number
    completedCount: number
    abandonedCount: number
    totalRetries: number
    avgRetries: number
    tasksWithRetries: number
    inputTokens: number
    outputTokens: number
    avgSessionMinutes: number
  }

  const byTool = db
    .prepare(
      `SELECT t.source_tool AS sourceTool, COUNT(*) AS count, COALESCE(SUM(t.retry_count), 0) AS retries
       FROM tasks t ${where}
       GROUP BY t.source_tool ORDER BY count DESC`,
    )
    .all(...params) as { sourceTool: string; count: number; retries: number }[]

  const byStatus = db
    .prepare(
      `SELECT t.status AS status, COUNT(*) AS count
       FROM tasks t ${where}
       GROUP BY t.status ORDER BY count DESC`,
    )
    .all(...params) as { status: string; count: number }[]

  const byEventType = db
    .prepare(
      `SELECT e.event_type AS eventType, COUNT(*) AS count
       FROM task_events e
       INNER JOIN tasks t ON t.id = e.task_id
       ${where}
       GROUP BY e.event_type
       ORDER BY count DESC`,
    )
    .all(...params) as { eventType: string; count: number }[]

  const eventLookup = Object.fromEntries(byEventType.map((r) => [r.eventType, r.count]))

  const byModel = aggregateModelStats(db, where, params, filters.model)
  const estimatedCostUsd = totalEstimatedCost(byModel)

  const retryTrend = db
    .prepare(
      `SELECT substr(t.started_at, 1, 10) AS day,
              COALESCE(SUM(t.retry_count), 0) AS retries,
              COUNT(*) AS tasks
       FROM tasks t ${where}
       GROUP BY substr(t.started_at, 1, 10)
       ORDER BY day ASC
       LIMIT 30`,
    )
    .all(...params) as { day: string; retries: number; tasks: number }[]

  const topRetryTasks = db
    .prepare(
      `SELECT t.id, t.title, t.source_tool AS sourceTool, t.retry_count AS retryCount,
              t.status, t.started_at AS startedAt
       FROM tasks t ${where}
       ORDER BY t.retry_count DESC, t.started_at DESC
       LIMIT 12`,
    )
    .all(...params) as AgenticDashboard['topRetryTasks']

  // Per-agent summary
  const byAgent = db
    .prepare(
      `SELECT
        a.id AS agentId,
        a.name AS agentName,
        COUNT(t.id) AS taskCount,
        COALESCE(SUM(t.retry_count), 0) AS retryCount,
        COALESCE(SUM(t.input_tokens), 0) AS inputTokens,
        COALESCE(SUM(t.output_tokens), 0) AS outputTokens,
        COALESCE(AVG(
          CASE WHEN t.ended_at IS NOT NULL
            THEN (julianday(t.ended_at) - julianday(t.started_at)) * 24 * 3600
            ELSE NULL END
        ), 0) AS avgDurationSec
       FROM agents a
       LEFT JOIN tasks t ON t.agent_id = a.id ${where}
       GROUP BY a.id
       ORDER BY taskCount DESC
       LIMIT 20`,
    )
    .all(...params) as {
    agentId: string
    agentName: string
    taskCount: number
    retryCount: number
    inputTokens: number
    outputTokens: number
    avgDurationSec: number
  }[]

  // Tasks by repo
  const byRepo = db
    .prepare(
      `SELECT
        COALESCE(t.repo_name, '(unknown)') AS repoName,
        COUNT(*) AS taskCount,
        COALESCE(SUM(t.retry_count), 0) AS retryCount,
        COALESCE(SUM(CASE WHEN t.status = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS completedCount,
        COUNT(*) AS totalCount
       FROM tasks t ${where}
       GROUP BY t.repo_name
       ORDER BY taskCount DESC
       LIMIT 15`,
    )
    .all(...params) as {
    repoName: string
    taskCount: number
    retryCount: number
    completedCount: number
    totalCount: number
  }[]

  // Duration histogram (completed tasks only)
  const durationDistribution = db
    .prepare(
      `SELECT
        CASE
          WHEN (julianday(t.ended_at) - julianday(t.started_at)) * 86400 < 30 THEN '0-30s'
          WHEN (julianday(t.ended_at) - julianday(t.started_at)) * 86400 < 60 THEN '30-60s'
          WHEN (julianday(t.ended_at) - julianday(t.started_at)) * 86400 < 300 THEN '1-5m'
          WHEN (julianday(t.ended_at) - julianday(t.started_at)) * 86400 < 900 THEN '5-15m'
          WHEN (julianday(t.ended_at) - julianday(t.started_at)) * 86400 < 3600 THEN '15-60m'
          ELSE '60m+'
        END AS bucket,
        COUNT(*) AS count
       FROM tasks t
       ${where ? `${where} AND` : 'WHERE'} t.ended_at IS NOT NULL
       GROUP BY bucket
       ORDER BY
        CASE bucket
          WHEN '0-30s' THEN 1
          WHEN '30-60s' THEN 2
          WHEN '1-5m' THEN 3
          WHEN '5-15m' THEN 4
          WHEN '15-60m' THEN 5
          WHEN '60m+' THEN 6
          ELSE 7
        END`,
    )
    .all(...params) as { bucket: string; count: number }[]

  // Daily completed vs abandoned
  const dailyCompletionRate = db
    .prepare(
      `SELECT
        substr(t.started_at, 1, 10) AS day,
        COALESCE(SUM(CASE WHEN t.status = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS completed,
        COALESCE(SUM(CASE WHEN t.status = 'ABANDONED' THEN 1 ELSE 0 END), 0) AS abandoned,
        COUNT(*) AS total
       FROM tasks t ${where}
       GROUP BY substr(t.started_at, 1, 10)
       ORDER BY day ASC
       LIMIT 30`,
    )
    .all(...params) as { day: string; completed: number; abandoned: number; total: number }[]

  // Hourly activity (events by hour of day)
  const hourlyActivity = db
    .prepare(
      `SELECT
        CAST(strftime('%H', e.occurred_at) AS INTEGER) AS hour,
        COUNT(*) AS count
       FROM task_events e
       INNER JOIN tasks t ON t.id = e.task_id
       ${where}
       GROUP BY hour
       ORDER BY hour ASC`,
    )
    .all(...params) as { hour: number; count: number }[]

  // Retry rate by model
  const modelRetryRaw = db
    .prepare(
      `SELECT
        json_extract(e.payload_json, '$.model') AS model,
        t.retry_count AS retryCount,
        t.id AS taskId
       FROM task_events e
       INNER JOIN tasks t ON t.id = e.task_id
       ${where ? `${where} AND` : 'WHERE'} e.event_type = 'TOKEN_USAGE'
         AND e.payload_json IS NOT NULL
       ORDER BY e.occurred_at DESC`,
    )
    .all(...params) as { model: string | null; retryCount: number; taskId: string }[]

  const modelRetryMap = new Map<string, { taskIds: Set<string>; tasksWithRetries: number; taskCount: number }>()
  for (const row of modelRetryRaw) {
    const m = row.model || 'unknown'
    if (filters.model && !m.toLowerCase().includes(filters.model.toLowerCase())) continue
    let cur = modelRetryMap.get(m)
    if (!cur) {
      cur = { taskIds: new Set(), tasksWithRetries: 0, taskCount: 0 }
      modelRetryMap.set(m, cur)
    }
    if (!cur.taskIds.has(row.taskId)) {
      cur.taskIds.add(row.taskId)
      cur.taskCount += 1
      // Count once per unique task: whether it had at least one retry
      if (row.retryCount > 0) {
        cur.tasksWithRetries += 1
      }
    }
  }
  const byModelRetryRate = [...modelRetryMap.entries()]
    .map(([model, stats]) => ({
      model,
      totalTasks: stats.taskCount,
      totalRetries: 0, // unused by the chart; kept for schema compatibility
      retryRate: stats.taskCount ? stats.tasksWithRetries / stats.taskCount : 0,
    }))
    .sort((a, b) => b.retryRate - a.retryRate)
    .slice(0, 15)

  // Agent health
  const now = Date.now()
  const staleThreshold = (config.staleAgentSeconds || 300) * 1000
  const agentHealth = (
    db
      .prepare(
        `SELECT
          a.id AS agentId,
          a.name AS agentName,
          a.last_heartbeat_at AS lastHeartbeatAt,
          COALESCE((SELECT COUNT(*) FROM task_events e2 WHERE e2.task_id IN (SELECT id FROM tasks WHERE agent_id = a.id) AND e2.event_type = 'SESSION_START'), 0) AS totalSessions,
          COALESCE((SELECT COUNT(*) FROM tasks WHERE agent_id = a.id AND status = 'ACTIVE'), 0) AS activeTasks
         FROM agents a
         ORDER BY a.last_heartbeat_at DESC`,
      )
      .all() as {
      agentId: string
      agentName: string
      lastHeartbeatAt: string | null
      totalSessions: number
      activeTasks: number
    }[]
  ).map((a) => ({
    ...a,
    stale: !a.lastHeartbeatAt || now - Date.parse(a.lastHeartbeatAt) > staleThreshold,
  }))

  // Previous period computation for live deltas
  const prevFilters: DashboardFilters = { ...filters }
  const comparisonAvailable = Boolean(filters.from)
  if (filters.from) {
    const windowMs = Date.now() - new Date(filters.from).getTime()
    if (windowMs > 0) {
      const prevTo = new Date(new Date(filters.from).getTime() - 1).toISOString()
      const prevFrom = new Date(new Date(filters.from).getTime() - windowMs).toISOString()
      prevFilters.from = prevFrom
      prevFilters.to = prevTo
    }
  }
  const { sql: prevWhere, params: prevParams } = taskWhere(prevFilters)
  const prevTotals = comparisonAvailable
    ? (db
        .prepare(
          `SELECT
        COALESCE(COUNT(*), 0) AS taskCount,
        COALESCE(SUM(CASE WHEN t.status = 'ACTIVE' THEN 1 ELSE 0 END), 0) AS activeCount,
        COALESCE(SUM(CASE WHEN t.status = 'COMPLETED' THEN 1 ELSE 0 END), 0) AS completedCount,
        COALESCE(SUM(CASE WHEN t.status = 'ABANDONED' THEN 1 ELSE 0 END), 0) AS abandonedCount,
        COALESCE(SUM(t.retry_count), 0) AS totalRetries,
        COALESCE(AVG(t.retry_count), 0) AS avgRetries,
        COALESCE(SUM(CASE WHEN t.retry_count > 0 THEN 1 ELSE 0 END), 0) AS tasksWithRetries,
        COALESCE(SUM(t.input_tokens), 0) AS inputTokens,
        COALESCE(SUM(t.output_tokens), 0) AS outputTokens,
        COALESCE(AVG(
          CASE WHEN t.ended_at IS NOT NULL
            THEN (julianday(t.ended_at) - julianday(t.started_at)) * 24 * 60
            ELSE NULL END
        ), 0) AS avgSessionMinutes
       FROM tasks t ${prevWhere}`,
        )
        .get(...prevParams) as {
        taskCount: number
        activeCount: number
        completedCount: number
        abandonedCount: number
        totalRetries: number
        avgRetries: number
        tasksWithRetries: number
        inputTokens: number
        outputTokens: number
        avgSessionMinutes: number
      })
    : {
        taskCount: 0,
        activeCount: 0,
        completedCount: 0,
        abandonedCount: 0,
        totalRetries: 0,
        avgRetries: 0,
        tasksWithRetries: 0,
        inputTokens: 0,
        outputTokens: 0,
        avgSessionMinutes: 0,
      }
  const prevAgentCount = comparisonAvailable
    ? ((db
        .prepare(`SELECT COUNT(DISTINCT t.agent_id) AS c FROM tasks t ${prevWhere}`)
        .get(...prevParams) as { c: number }).c ?? 0)
    : 0

  const agentCount = (
    db.prepare(`SELECT COUNT(DISTINCT t.agent_id) AS c FROM tasks t ${where}`).get(...params) as { c: number }
  ).c
  const finished = totals.completedCount + totals.abandonedCount
  const completionRate = finished ? totals.completedCount / finished : 0
  const abandonRate = finished ? totals.abandonedCount / finished : 0
  const retryRate = totals.taskCount ? totals.tasksWithRetries / totals.taskCount : 0
  const prevRetryRate = prevTotals.taskCount ? prevTotals.tasksWithRetries / prevTotals.taskCount : 0
  const prevEstimatedCostUsd = comparisonAvailable
    ? totalEstimatedCost(aggregateModelStats(db, prevWhere, prevParams, filters.model))
    : 0

  return {
    filters,
    ...totals,
    completionRate,
    abandonRate,
    retryRate,
    agentCount,
    prevTaskCount: prevTotals.taskCount,
    prevTotalRetries: prevTotals.totalRetries,
    prevActiveCount: prevTotals.activeCount,
    prevCompletedCount: prevTotals.completedCount,
    prevAbandonedCount: prevTotals.abandonedCount,
    prevInputTokens: prevTotals.inputTokens,
    prevOutputTokens: prevTotals.outputTokens,
    prevAvgRetries: prevTotals.avgRetries,
    prevRetryRate,
    prevAgentCount,
    prevAvgSessionMinutes: prevTotals.avgSessionMinutes,
    estimatedCostUsd,
    prevEstimatedCostUsd,
    sessionStarts: eventLookup.SESSION_START || 0,
    sessionEnds: eventLookup.SESSION_END || 0,
    subagentEvents: eventLookup.SUBAGENT || 0,
    compactionEvents: eventLookup.COMPACTION || 0,
    byTool,
    byEventType,
    byStatus,
    byModel,
    retryTrend,
    topRetryTasks,
    byAgent,
    byRepo: byRepo.map((r) => ({
      ...r,
      completionRate: r.totalCount ? r.completedCount / r.totalCount : 0,
    })),
    durationDistribution,
    dailyCompletionRate,
    hourlyActivity,
    byModelRetryRate,
    agentHealth,
    availableTools: (
      db.prepare('SELECT DISTINCT source_tool AS v FROM tasks ORDER BY v').all() as { v: string }[]
    ).map((r) => r.v),
    availableModels: (
      (() => {
        // Models that have actually been used (from TOKEN_USAGE events)
        const loggedModels: string[] = (
          db
            .prepare(
              `SELECT DISTINCT json_extract(payload_json, '$.model') AS v
               FROM task_events WHERE event_type = 'TOKEN_USAGE' AND payload_json IS NOT NULL
               ORDER BY v`,
            )
            .all() as { v: string | null }[]
        )
          .map((r) => r.v)
          .filter((v): v is string => !!v)

        // Merge with all known model rates so configured LLMs (e.g. DeepSeekV4)
        // show up in the filter dropdown even before they've been used
        const knownModels = new Set(Object.keys(MODEL_RATES))
        const merged = new Set([...loggedModels, ...knownModels])
        return [...merged].sort()
      })()
    ),
    availableAgents: (
      db.prepare('SELECT id, name FROM agents ORDER BY name').all() as { id: string; name: string }[]
    ),
  }
}

export type TimelineEvent = {
  id: string
  eventType: string
  occurredAt: string
  summary: string
  isRetrySignal: boolean
  payload: Record<string, unknown> | null
}

const RETRY_TYPES = new Set(['EDIT', 'TEST_FAIL', 'DIFF_REJECTED', 'COMPACTION'])

export function getTaskTimeline(taskId: string): TimelineEvent[] {
  const rows = getDb()
    .prepare(
      `SELECT id, event_type, payload_json, occurred_at
       FROM task_events WHERE task_id = ? ORDER BY occurred_at ASC, created_at ASC`,
    )
    .all(taskId) as {
    id: string
    event_type: string
    payload_json: string | null
    occurred_at: string
  }[]

  return rows.map((r) => {
    let payload: Record<string, unknown> | null = null
    try {
      payload = r.payload_json ? JSON.parse(r.payload_json) : null
    } catch {
      payload = null
    }
    return {
      id: r.id,
      eventType: r.event_type,
      occurredAt: r.occurred_at,
      summary: summarizeEvent(r.event_type, payload),
      isRetrySignal: RETRY_TYPES.has(r.event_type),
      payload,
    }
  })
}

function summarizeEvent(type: string, payload: Record<string, unknown> | null): string {
  if (type === 'TOKEN_USAGE' && payload) {
    return `${payload.model || 'model'}  in=${payload.inputTokens ?? 0}  out=${payload.outputTokens ?? 0}`
  }
  if (type === 'SUBAGENT' && payload?.name) return `subagent ${payload.name}`
  if (payload?.note) return String(payload.note)
  if (payload?.test) return `test ${payload.test}`
  return type.replaceAll('_', ' ').toLowerCase()
}
