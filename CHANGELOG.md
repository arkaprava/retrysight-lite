# Changelog

All notable changes to RetrySight Lite are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.1](https://github.com/arkaprava/retrysight-lite/releases/tag/v1.1.1) - 2026-10-02

### Changed

- Releases are now automated: pushing a `v*` tag builds all platforms, publishes to the download CDN, and creates a GitHub Release. No application changes from 1.1.0. See [#5](https://github.com/arkaprava/retrysight-lite/pull/5).

## [1.1.0](https://github.com/arkaprava/retrysight-lite/releases/tag/v1.1.0) - 2026-10-01

### Fixed

- `retry_count` and token-usage accounting were badly inflated for real Claude Code CLI transcripts: almost every line of a session (chat turns, tool results, bookkeeping lines) was being counted as a retry. Classification now correctly distinguishes genuine retry signals (failed tool calls, mutating edits, test failures, rejected diffs, compaction) from normal agent activity. See [#2](https://github.com/arkaprava/retrysight-lite/pull/2).
- Added a one-off backfill script (`manager/scripts/reclassify-claude-code-events.ts`) to correct existing `task_events`/`tasks.retry_count` data ingested under the old logic.

## [1.0.0](https://github.com/arkaprava/retrysight-lite/releases/tag/v1.0.0) - 2026-08-05

### Added

- Open-source release under Apache-2.0.
- Flutter desktop app with dashboard, tasks, collectors, MCP, and settings screens.
- Cost-related dashboard KPIs (estimated spend, cost per task, cost per 1M tokens, top model).
- Live KPI refresh indicators and period-over-period deltas on the dashboard.
- Bundled tool icons for coding-agent identification.

