// SPDX-License-Identifier: Apache-2.0

import { createRequire } from 'node:module'
import { join } from 'node:path'
import { config } from './config.js'
import { barChart, fmtNum, kpiLine, pct, sparkline } from './charts.js'
import {
  DashboardFilters,
  getAgenticDashboard,
  getTaskTimeline,
} from './metrics.js'
import { getTask, listTasks } from './ingest.js'
import { buildMcpConfig } from './graphql.js'

type Blessed = {
  screen: (opts?: Record<string, unknown>) => {
    key: (keys: string | string[], handler: () => void) => void
    on: (event: string, handler: () => void) => void
    render: () => void
    destroy: () => void
  }
  box: (opts?: Record<string, unknown>) => {
    setContent: (text: string) => void
    setLabel: (text: string) => void
    scroll: (offset: number) => void
  }
}

// See the matching comment in config.ts: `import.meta.url` is empty when this
// file is bundled to CJS by esbuild for the `pkg`-packaged desktop app. This
// used to blow up at *import* time (createRequire(undefined), then
// `require('blessed')` failing pkg's static asset detection since it goes
// through a dynamically-constructed `require`) — before `--headless` was even
// checked, crashing the packaged binary on every launch. `blessed` is now
// loaded lazily, only when the TUI actually starts, so the headless
// embedded-backend path (the only path the desktop app uses) never touches it.
function moduleUrl(): string {
  try {
    return import.meta.url || (() => { throw new Error('empty import.meta.url') })()
  } catch {
    return `file://${join(process.cwd(), 'index.js')}`
  }
}

let blessedModule: Blessed | null = null
function loadBlessed(): Blessed {
  if (!blessedModule) {
    const require = createRequire(moduleUrl())
    blessedModule = require('blessed') as Blessed
  }
  return blessedModule
}

type View = 'dashboard' | 'tasks' | 'task' | 'mcp'

/** Render a bordered table from labeled rows + header. */
function llmTable(
  rows: { model: string; tokens: string; cost: string; events: string }[],
): string {
  if (!rows.length) return '{gray-fg}no LLM token events yet{/}'
  const widths = [0, 0, 0, 0]
  const headers = ['Model', 'Tokens', 'Cost', 'Events']
  const data = [headers, ...rows.map((r) => [r.model, r.tokens, r.cost, r.events])]
  for (const row of data) {
    for (let c = 0; c < 4; c++) {
      if ((row[c]?.length ?? 0) > widths[c]) widths[c] = row[c].length
    }
  }
  // Clamp widths
  widths[0] = Math.min(widths[0], 30)
  for (let c = 1; c < 4; c++) widths[c] = Math.max(widths[c] + 2, 10)
  const hRule = `─`.repeat(widths[0] + 2) + `┬` + `─`.repeat(widths[1] + 2) + `┬` + `─`.repeat(widths[2] + 2) + `┬` + `─`.repeat(widths[3] + 2)
  const lines: string[] = [`┌${hRule}┐`]
  for (let i = 0; i < data.length; i++) {
    const [m, t, c_, e] = data[i]
    const padded = [
      m.padEnd(widths[0]),
      t.padStart(widths[1]),
      c_.padStart(widths[2]),
      e.padStart(widths[3]),
    ]
    if (i === 0) {
      // header row
      lines.push(`│ {bold}{blue-fg}${padded[0]}{/} │ ${padded[1]} │ ${padded[2]} │ ${padded[3]} │`)
      lines.push(`├${hRule.replace(/┬/g, '┼').replace(/^─/, '─').replace(/─$/, '─')}┤`)
    } else {
      const modelStyle =
        rows[i - 1].model.length > 26
          ? `{gray-fg}${padded[0].slice(0, 24)}..{/}`
          : `{fg}${padded[0]}{/}`
      lines.push(`│ ${modelStyle} │ ${padded[1]} │ ${padded[2]} │ {violet-fg}${padded[3]}{/} │`)
    }
  }
  const endRule = hRule.replace(/┬/g, '┴').replace(/^─/, '─').replace(/─$/, '─')
  lines.push(`└${endRule}┘`)
  return lines.join('\n')
}

/* ─── Solarized Light (Ethan Schoonover) ─── */
const THEME = {
  bg: '#fdf6e3',       // base3
  fg: '#657b83',       // base00 — primary text
  muted: '#93a1a1',    // base1 — comments/secondary
  accent: '#268bd2',   // blue
  border: '#eee8d5',   // base2
  warn: '#b58900',     // yellow
  danger: '#dc322f',    // red
  green: '#859900',
  cyan: '#2aa198',
  violet: '#6c71c4',
  orange: '#cb4b16',
  magenta: '#d33682',
  emphasized: '#586e75', // base01
  base02: '#073642',
  base03: '#002b36',
}

export function startTui(apiPort: number) {
  const blessed = loadBlessed()
  const screen = blessed.screen({
    smartCSR: true,
    title: 'RetrySight Lite',
    fullUnicode: true,
  })

  let view: View = 'dashboard'
  let selectedTaskId: string | null = null
  let taskCursor = 0
  let filterIndex = 0 // 0 range, 1 tool, 2 model, 3 agent
  const filters: DashboardFilters = {}
  const rangeOptions = ['all', '24h', '7d', '30d'] as const
  let rangeIdx = 0
  let toolIdx = 0
  let modelIdx = 0
  let agentIdx = 0

  const header = blessed.box({
    parent: screen,
    top: 0,
    left: 0,
    width: '100%',
    height: 3,
    tags: true,
    style: { fg: THEME.fg, bg: THEME.bg },
  })

  const nav = blessed.box({
    parent: screen,
    top: 3,
    left: 0,
    width: 22,
    height: '100%-5',
    label: ' {bold}Nav{/bold} ',
    tags: true,
    border: { type: 'line' },
    style: {
      fg: THEME.fg,
      bg: THEME.bg,
      border: { fg: THEME.border },
      label: { fg: THEME.accent },
    },
  })

  const main = blessed.box({
    parent: screen,
    top: 3,
    left: 22,
    width: '100%-22',
    height: '100%-5',
    label: ' {bold}Dashboard{/bold} ',
    tags: true,
    border: { type: 'line' },
    scrollable: true,
    alwaysScroll: true,
    keys: true,
    vi: true,
    mouse: true,
    scrollbar: { ch: '│', style: { fg: THEME.accent } },
    style: {
      fg: THEME.fg,
      bg: THEME.bg,
      border: { fg: THEME.border },
      label: { fg: THEME.accent },
    },
  })

  const footer = blessed.box({
    parent: screen,
    bottom: 0,
    left: 0,
    width: '100%',
    height: 2,
    tags: true,
    style: { fg: THEME.muted, bg: THEME.bg },
  })

  function applyRange() {
    const r = rangeOptions[rangeIdx]
    const now = Date.now()
    if (r === 'all') {
      delete filters.from
      delete filters.to
      return
    }
    const ms =
      r === '24h' ? 86_400_000 : r === '7d' ? 7 * 86_400_000 : 30 * 86_400_000
    filters.from = new Date(now - ms).toISOString()
    delete filters.to
  }

  function syncFilterDims(dash = getAgenticDashboard(filters)) {
    const tools = ['(any)', ...dash.availableTools]
    const models = ['(any)', ...dash.availableModels]
    const agents = ['(any)', ...dash.availableAgents.map((a) => a.name)]
    if (toolIdx >= tools.length) toolIdx = 0
    if (modelIdx >= models.length) modelIdx = 0
    if (agentIdx >= agents.length) agentIdx = 0

    filters.sourceTool = toolIdx === 0 ? undefined : tools[toolIdx]
    filters.model = modelIdx === 0 ? undefined : models[modelIdx]
    filters.agentId =
      agentIdx === 0 ? undefined : dash.availableAgents[agentIdx - 1]?.id
    applyRange()
    return { tools, models, agents, dash: getAgenticDashboard(filters) }
  }

  function navMarkup() {
    const item = (key: string, label: string, id: View) => {
      const active = view === id || (id === 'tasks' && view === 'task')
      return active
        ? `{white-fg}{${THEME.accent}-bg} ${key} ${label.padEnd(12)} {/}`
        : ` ${key} ${label}`
    }
    return [
      '',
      item('1', 'Dashboard', 'dashboard'),
      item('2', 'Tasks', 'tasks'),
      item('3', 'MCP', 'mcp'),
      '',
      '{gray-fg}────────────────{/}',
      '{gray-fg} filters (dash){/}',
      '{gray-fg} f  cycle field{/}',
      '{gray-fg} [/] change val{/}',
      '{gray-fg} r  refresh{/}',
      '{gray-fg} q  quit{/}',
    ].join('\n')
  }

  function renderDashboard() {
    const { tools, models, agents, dash } = syncFilterDims()
    const fieldNames = ['range', 'tool', 'model', 'agent']
    const fieldVals = [
      rangeOptions[rangeIdx],
      tools[toolIdx],
      models[modelIdx],
      agents[agentIdx],
    ]
    const filterLine = fieldNames
      .map((name, i) => {
        const body = `${name}:${fieldVals[i]}`
        return i === filterIndex ? `{${THEME.accent}-fg}{bold}[${body}]{/}` : `{${THEME.muted}-fg}${body}{/}`
      })
      .join('  ')

    const kpis = [
      kpiLine('Tasks', fmtNum(dash.taskCount)),
      kpiLine('Retries', fmtNum(dash.totalRetries)),
      kpiLine('Retry rate', pct(dash.retryRate)),
      kpiLine('Avg retries', fmtNum(dash.avgRetries)),
      kpiLine('Completed', `${fmtNum(dash.completedCount)} (${pct(dash.completionRate)})`),
      kpiLine('Abandoned', `${fmtNum(dash.abandonedCount)} (${pct(dash.abandonRate)})`),
      kpiLine('Active', fmtNum(dash.activeCount)),
      kpiLine('Avg session', `${fmtNum(dash.avgSessionMinutes)}m`),
      kpiLine('Tokens in/out', `${fmtNum(dash.inputTokens)} / ${fmtNum(dash.outputTokens)}`),
      kpiLine('Sessions', `${dash.sessionStarts}→${dash.sessionEnds}`),
      kpiLine('Subagents', fmtNum(dash.subagentEvents)),
      kpiLine('Compactions', fmtNum(dash.compactionEvents)),
      kpiLine('Agents', fmtNum(dash.agentCount)),
    ].join('\n')

    const toolBars = barChart(
      dash.byTool.map((t) => ({ label: t.sourceTool, value: t.count })),
      28,
      6,
    ).join('\n') || '{gray-fg}no tasks yet{/}'

    const eventBars = barChart(
      dash.byEventType.map((e) => ({ label: e.eventType, value: e.count })),
      28,
      8,
    ).join('\n') || '{gray-fg}no events yet{/}'

    const trend = sparkline(dash.retryTrend.map((d) => d.retries), 42)
    const taskTrend = sparkline(dash.retryTrend.map((d) => d.tasks), 42)

    const llmRows = dash.byModel.slice(0, 8).map((m) => ({
      model: m.model,
      tokens: fmtNum(m.inputTokens + m.outputTokens),
      cost: `~$${m.estimatedCostUsd.toFixed(3)}`,
      events: String(m.events),
    }))
    const llmSection = llmTable(llmRows)

    const top =
      dash.topRetryTasks
        .slice(0, 6)
        .map(
          (t, i) =>
            `${String(i + 1).padStart(2)}. [{#cb4b16-fg}${t.retryCount}{/}] ${((t.title || t.id).slice(0, 40)).padEnd(40)} ${t.sourceTool}`,
        )
        .join('\n') || '{gray-fg}no retry leaders{/}'

    main.setLabel(' {bold}{blue-fg}Dashboard{/bold} · agentic metrics ')
    main.setContent(
      [
        `{bold}{${THEME.emphasized}-fg}RetrySight Lite{/}  {${THEME.muted}-fg}single-user terminal console{/}`,
        filterLine,
        '',
        `{bold}{${THEME.cyan}-fg}┃ KPIs{/}`,
        kpis,
        '',
        `{bold}{${THEME.cyan}-fg}┃ Retries over time{/}  ` + `{${THEME.green}-fg}${trend}{/}`,
        `{bold}{${THEME.cyan}-fg}┃ Tasks over time{/}   ` + `{${THEME.green}-fg}${taskTrend}{/}`,
        '',
        `{bold}{${THEME.cyan}-fg}┃ By source tool{/}`,
        toolBars,
        '',
        `{bold}{${THEME.cyan}-fg}┃ Event types (agentic){/}`,
        eventBars,
        '',
        `{bold}{${THEME.cyan}-fg}┃ LLM / models{/}`,
        llmSection,
        '',
        `{bold}{${THEME.cyan}-fg}┃ Top retry tasks{/}  {${THEME.muted}-fg}(open Tasks to inspect timeline){/}`,
        top,
      ].join('\n'),
    )
  }

  function renderTasks() {
    applyRange()
    const { items, totalCount } = listTasks({
      ...filters,
      size: 80,
      page: 0,
    })
    if (taskCursor >= items.length) taskCursor = Math.max(0, items.length - 1)
    const lines = items.map((t, i) => {
      const mark = i === taskCursor ? `{${THEME.base03}-fg}{${THEME.base02}-bg}` : ''
      const end = i === taskCursor ? '{/}' : ''
      const title = (t.title || t.id).slice(0, 36).padEnd(36)
      return `${mark}${String(i + 1).padStart(3)}. ${title}  {${THEME.muted}-fg}${t.source_tool.padEnd(12)}{/}  r=${String(t.retry_count).padStart(3)}  ${t.status}${end}`
    })
    main.setLabel(` {bold}Tasks{/bold} · ${totalCount} `)
    main.setContent(
      [
        '{gray-fg}↑↓ select · Enter open timeline · Esc back{/}',
        '',
        ...lines,
        items.length ? '' : '{gray-fg}No tasks. Start the Kotlin agent or run npm run seed.{/}',
      ].join('\n'),
    )
    return items
  }

  function renderTaskDetail() {
    if (!selectedTaskId) {
      view = 'tasks'
      return renderTasks()
    }
    const task = getTask(selectedTaskId)
    const timeline = getTaskTimeline(selectedTaskId)
    if (!task) {
      main.setContent('{red-fg}Task not found{/}')
      return
    }

    const headerLines = [
      `{bold}{${THEME.emphasized}-fg}${task.title || task.id}{/}`,
      `{${THEME.muted}-fg}${task.source_tool} · ${task.status} · retries ${task.retry_count} · tokens ${task.input_tokens}/${task.output_tokens}{/}`,
      `{${THEME.muted}-fg}${task.repo_name || ''} ${task.git_branch || ''} ${task.project_root || ''}{/}`,
      '',
      `{bold}{${THEME.cyan}-fg}┃ Waterfall timeline{/}`,
    ]

    // Determine nesting depth for each event.
    // SUBAGENT opens a child level; top-level events (session bookends,
    // compaction) reset back to root so the waterfall stays readable.
    const topLevel = new Set(['SESSION_START', 'SESSION_END', 'COMPACTION'])
    const depths = new Array<number>(timeline.length)
    let depth = 0
    for (let i = 0; i < timeline.length; i++) {
      const e = timeline[i]
      if (topLevel.has(e.eventType)) depth = 0
      depths[i] = depth
      if (e.eventType === 'SUBAGENT') depth++
    }

    // Precompute sibling & continuity info for tree-drawing connectors
    const hasNextSibling = new Array<boolean>(timeline.length)
    for (let i = 0; i < timeline.length; i++) {
      let sib = false
      for (let j = i + 1; j < timeline.length; j++) {
        if (depths[j] === depths[i]) { sib = true; break }
        if (depths[j] < depths[i]) break
      }
      hasNextSibling[i] = sib
    }

    // cont[i][lv] = does a future event exist at depth ≤ lv?
    const cont: boolean[][] = []
    for (let i = 0; i < timeline.length; i++) {
      cont[i] = []
      for (let lv = 0; lv < depths[i]; lv++) {
        let c = false
        for (let j = i + 1; j < timeline.length; j++) {
          if (depths[j] <= lv) { c = true; break }
        }
        cont[i][lv] = c
      }
    }

    const waterfallLines = timeline.map((e, i) => {
      const d = depths[i]

      // Build tree-drawing prefix
      // Each ancestor level (0 … d-2) gets "│  " if that column continues, else "   "
      // The parent level (d-1) gets "├─ " or "└─ " based on siblings
      let prefix = ''
      for (let lv = 0; lv < d; lv++) {
        if (lv < d - 1) {
          prefix += cont[i][lv] ? '│  ' : '   '
        } else {
          prefix += hasNextSibling[i] ? '├─ ' : '└─ '
        }
      }

      const ts = e.occurredAt.replace('T', ' ').slice(0, 19)
      const flag = e.isRetrySignal
        ? `{${THEME.warn}-fg}●{/}`
        : `{${THEME.muted}-fg}○{/}`
      const type = e.eventType.padEnd(14)
      return `${prefix}${flag} {${THEME.muted}-fg}${ts}{/}  {bold}${type}{/}  ${e.summary}`
    })

    main.setLabel(' {bold}Task waterfall{/bold} ')
    main.setContent(
      [
        ...headerLines,
        ...(waterfallLines.length ? waterfallLines : ['{gray-fg}No events{/}']),
        '',
        '{gray-fg}Esc → tasks{/}',
      ].join('\n'),
    )
  }


  function renderMcp() {
    const cfg = buildMcpConfig()
    main.setLabel(' {bold}MCP{/bold} ')
    main.setContent(
      [
        `{bold}{${THEME.emphasized}-fg}IDE / MCP config{/}`,
        `{${THEME.muted}-fg}No authentication needed — connects to local GraphQL endpoint.{/}`,
        '',
        `{${THEME.accent}-fg}Endpoint{/}  ${cfg.endpointHint}`,
        `{${THEME.accent}-fg}Command{/}   ${cfg.command} ${cfg.args.join(' ')}`,
        '',
        '{bold}configJson{/}',
        cfg.configJson,
      ].join('\n'),
    )
  }

  function render() {
    header.setContent(
      ` {bold}{${THEME.emphasized}-fg} RetrySight Lite {/} {${THEME.muted}-fg}standalone{/}    api :${apiPort}    db ${config.dbPath}`,
    )
    nav.setContent(navMarkup())
    if (view === 'dashboard') renderDashboard()
    else if (view === 'tasks') renderTasks()
    else if (view === 'task') renderTaskDetail()
    else if (view === 'mcp') renderMcp()

    footer.setContent(
      ` {${THEME.muted}-fg}1-3 views · f filter field · [ ] filter value · r refresh · Enter task · q quit{/}`,
    )
    screen.render()
  }

  screen.key(['q', 'C-c'], () => process.exit(0))
  screen.key(['r'], () => render())
  screen.key(['1'], () => {
    view = 'dashboard'
    render()
  })
  screen.key(['2'], () => {
    view = 'tasks'
    render()
  })
  screen.key(['3'], () => {
    view = 'mcp'
    render()
  })
  screen.key(['escape'], () => {
    if (view === 'task') view = 'tasks'
    render()
  })
  screen.key(['f'], () => {
    if (view !== 'dashboard') return
    filterIndex = (filterIndex + 1) % 4
    render()
  })
  screen.key([']'], () => {
    if (view !== 'dashboard') return
    const dash = getAgenticDashboard({})
    if (filterIndex === 0) rangeIdx = (rangeIdx + 1) % rangeOptions.length
    if (filterIndex === 1) toolIdx = (toolIdx + 1) % (dash.availableTools.length + 1)
    if (filterIndex === 2) modelIdx = (modelIdx + 1) % (dash.availableModels.length + 1)
    if (filterIndex === 3) agentIdx = (agentIdx + 1) % (dash.availableAgents.length + 1)
    render()
  })
  screen.key(['['], () => {
    if (view !== 'dashboard') return
    const dash = getAgenticDashboard({})
    if (filterIndex === 0) rangeIdx = (rangeIdx - 1 + rangeOptions.length) % rangeOptions.length
    if (filterIndex === 1)
      toolIdx = (toolIdx - 1 + dash.availableTools.length + 1) % (dash.availableTools.length + 1)
    if (filterIndex === 2)
      modelIdx = (modelIdx - 1 + dash.availableModels.length + 1) % (dash.availableModels.length + 1)
    if (filterIndex === 3)
      agentIdx = (agentIdx - 1 + dash.availableAgents.length + 1) % (dash.availableAgents.length + 1)
    render()
  })
  screen.key(['up', 'k'], () => {
    if (view === 'tasks') {
      taskCursor = Math.max(0, taskCursor - 1)
      render()
    } else {
      main.scroll(-1)
      screen.render()
    }
  })
  screen.key(['down', 'j'], () => {
    if (view === 'tasks') {
      taskCursor += 1
      render()
    } else {
      main.scroll(1)
      screen.render()
    }
  })
  screen.key(['enter'], () => {
    if (view !== 'tasks') return
    const items = listTasks({ ...filters, size: 80, page: 0 }).items
    const t = items[taskCursor]
    if (!t) return
    selectedTaskId = t.id
    view = 'task'
    render()
  })

  const timer = setInterval(() => {
    if (view === 'dashboard') render()
  }, 5000)
  screen.on('destroy', () => clearInterval(timer))

  render()
}
