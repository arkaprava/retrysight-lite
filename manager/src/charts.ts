// SPDX-License-Identifier: Apache-2.0

/** Terminal chart helpers for the RetrySight Lite TUI. */

export function barChart(
  items: { label: string; value: number }[],
  width = 36,
  maxBars = 8,
): string[] {
  const slice = items.slice(0, maxBars)
  const max = Math.max(1, ...slice.map((i) => i.value))
  return slice.map((item) => {
    const filled = Math.round((item.value / max) * width)
    const bar = '█'.repeat(filled) + '░'.repeat(Math.max(0, width - filled))
    const label = item.label.padEnd(14).slice(0, 14)
    return `${label} ${bar} ${item.value}`
  })
}

export function sparkline(values: number[], width = 40): string {
  if (!values.length) return '░'.repeat(width)
  const blocks = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
  const max = Math.max(1, ...values)
  const step = Math.max(1, Math.ceil(values.length / width))
  const sampled: number[] = []
  for (let i = 0; i < values.length; i += step) sampled.push(values[i])
  while (sampled.length < width) sampled.push(0)
  return sampled
    .slice(0, width)
    .map((v) => blocks[Math.min(blocks.length - 1, Math.round((v / max) * (blocks.length - 1)))])
    .join('')
}

export function kpiLine(label: string, value: string | number, width = 22): string {
  return `${label.padEnd(16)} ${String(value).padStart(width - 17)}`
}

export function pct(n: number): string {
  return `${(n * 100).toFixed(1)}%`
}

export function fmtNum(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`
  return String(Math.round(n * 100) / 100)
}
