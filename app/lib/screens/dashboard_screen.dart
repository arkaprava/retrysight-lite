import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/dashboard.dart';
import '../models/task.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/charts/chart_utils.dart';
import '../widgets/charts/dashboard_charts.dart';
import '../widgets/cursor_shell.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tool_icon.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, this.onOpenTask});

  final void Function(String taskId)? onOpenTask;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;
  DateTime _lastRefresh = DateTime.now();
  double _nowLineOffset = 0.0;
  int _nowHour = DateTime.now().hour;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {
        _lastRefresh = DateTime.now();
        _nowHour = DateTime.now().hour;
        _nowLineOffset =
            (DateTime.now().millisecondsSinceEpoch % 60000) / 60000;
      });
      final filters = ref.read(dashboardFiltersProvider);
      ref.invalidate(dashboardProvider(filters));
    });
  }

  int _toolIndex(DashboardFilters filters, List<String> tools) {
    if (filters.sourceTool == null) return 0;
    final idx = tools.indexOf(filters.sourceTool!);
    return idx < 0 ? 0 : idx + 1;
  }

  int _modelIndex(DashboardFilters filters, List<String> models) {
    if (filters.model == null) return 0;
    final idx = models.indexOf(filters.model!);
    return idx < 0 ? 0 : idx + 1;
  }

  int _agentIndex(DashboardFilters filters, List<AgentRef> agents) {
    if (filters.agentId == null) return 0;
    final idx = agents.indexWhere((a) => a.id == filters.agentId);
    return idx < 0 ? 0 : idx + 1;
  }

  void _cycleRange(DashboardFilters filters, int delta) {
    final values = DashboardRange.values;
    final next =
        values[(filters.range.index + delta + values.length) % values.length];
    ref.read(dashboardFiltersProvider.notifier).state = filters.copyWith(
      range: next,
    );
    ref.read(tasksPageProvider.notifier).state = 0;
  }

  void _cycleTool(DashboardFilters filters, List<String> tools, int delta) {
    final current = _toolIndex(filters, tools);
    final next = (current + delta).clamp(0, tools.length);
    ref.read(dashboardFiltersProvider.notifier).state = filters.copyWith(
      sourceTool: next == 0 ? null : tools[next - 1],
      clearSourceTool: next == 0,
    );
    ref.read(tasksPageProvider.notifier).state = 0;
  }

  void _cycleModel(DashboardFilters filters, List<String> models, int delta) {
    final current = _modelIndex(filters, models);
    final next = (current + delta).clamp(0, models.length);
    ref.read(dashboardFiltersProvider.notifier).state = filters.copyWith(
      model: next == 0 ? null : models[next - 1],
      clearModel: next == 0,
    );
    ref.read(tasksPageProvider.notifier).state = 0;
  }

  void _cycleAgent(DashboardFilters filters, List<AgentRef> agents, int delta) {
    final current = _agentIndex(filters, agents);
    final next = (current + delta).clamp(0, agents.length);
    ref.read(dashboardFiltersProvider.notifier).state = filters.copyWith(
      agentId: next == 0 ? null : agents[next - 1].id,
      clearAgentId: next == 0,
    );
    ref.read(tasksPageProvider.notifier).state = 0;
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(dashboardFiltersProvider);
    final dashAsync = ref.watch(dashboardProvider(filters));

    return dashAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LoadingError(
        error: e,
        onRetry: () {
          ref.invalidate(backendReadyProvider);
          ref.invalidate(dashboardProvider(filters));
        },
      ),
      data: (dash) {
        final maxTool = dash.byTool.isEmpty
            ? 1
            : dash.byTool.map((t) => t.count).reduce((a, b) => a > b ? a : b);
        final toolIdx = _toolIndex(filters, dash.availableTools);
        final modelIdx = _modelIndex(filters, dash.availableModels);
        final agentIdx = _agentIndex(filters, dash.availableAgents);
        final isRefreshing = dashAsync.isRefreshing;
        final compare = filters.hasComparisonPeriod;
        num? prev(num? value) => compare ? value : null;
        final deltaLabel = filters.comparisonDeltaLabel;
        final totalTokens = dash.inputTokens + dash.outputTokens;
        final costPerTask = dash.taskCount > 0
            ? dash.estimatedCostUsd / dash.taskCount
            : 0.0;
        final prevCostPerTask = dash.prevTaskCount > 0
            ? dash.prevEstimatedCostUsd / dash.prevTaskCount
            : 0.0;
        final costPer1MTokens = totalTokens > 0
            ? (dash.estimatedCostUsd / totalTokens) * 1_000_000
            : 0.0;
        final prevTotalTokens = dash.prevInputTokens + dash.prevOutputTokens;
        final prevCostPer1MTokens = prevTotalTokens > 0
            ? (dash.prevEstimatedCostUsd / prevTotalTokens) * 1_000_000
            : 0.0;
        final topCostModel = dash.byModel.isEmpty
            ? null
            : dash.byModel.reduce(
                (a, b) => a.estimatedCostUsd >= b.estimatedCostUsd ? a : b,
              );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: 'Range: ${filters.rangeLabel}',
                    onPrev: () => _cycleRange(filters, -1),
                    onNext: () => _cycleRange(filters, 1),
                  ),
                  _FilterChip(
                    label:
                        'Tool: ${toolIdx == 0 ? "(any)" : dash.availableTools.elementAtOrNull(toolIdx - 1) ?? "(any)"}',
                    onPrev: () => _cycleTool(filters, dash.availableTools, -1),
                    onNext: () => _cycleTool(filters, dash.availableTools, 1),
                  ),
                  _FilterChip(
                    label:
                        'Model: ${modelIdx == 0 ? "(any)" : dash.availableModels.elementAtOrNull(modelIdx - 1) ?? "(any)"}',
                    onPrev: () =>
                        _cycleModel(filters, dash.availableModels, -1),
                    onNext: () => _cycleModel(filters, dash.availableModels, 1),
                  ),
                  _FilterChip(
                    label:
                        'Agent: ${agentIdx == 0 ? "(any)" : dash.availableAgents.elementAtOrNull(agentIdx - 1)?.name ?? "(any)"}',
                    onPrev: () =>
                        _cycleAgent(filters, dash.availableAgents, -1),
                    onNext: () => _cycleAgent(filters, dash.availableAgents, 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CursorPanel(
                      title: 'Overview',
                      subtitle: 'Tasks, retries, and completion for the selected range',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Tasks',
                              value: dash.taskCount,
                              prevValue: prev(dash.prevTaskCount),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Retries',
                              value: dash.totalRetries,
                              prevValue: prev(dash.prevTotalRetries),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Retry rate',
                              value: dash.retryRate,
                              prevValue: prev(dash.prevRetryRate),
                              formatFn: (v) =>
                                  '${(v * 100).toStringAsFixed(1)}%',
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                              accentValue: true,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Avg retries',
                              value: dash.avgRetries,
                              prevValue: prev(dash.prevAvgRetries),
                              decimals: 2,
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Active',
                              value: dash.activeCount,
                              prevValue: prev(dash.prevActiveCount),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Completed',
                              value: dash.completedCount,
                              prevValue: prev(dash.prevCompletedCount),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Abandoned',
                              value: dash.abandonedCount,
                              prevValue: prev(dash.prevAbandonedCount),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Tokens in',
                              value: dash.inputTokens,
                              prevValue: prev(dash.prevInputTokens),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Tokens out',
                              value: dash.outputTokens,
                              prevValue: prev(dash.prevOutputTokens),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: LiveKpiCard(
                              label: 'Agents',
                              value: dash.agentCount,
                              prevValue: prev(dash.prevAgentCount),
                              deltaLabel: deltaLabel,
                              isRefreshing: isRefreshing,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CursorPanel(
                title: 'Cost',
                subtitle: 'Estimated spend from token usage, by model rates',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 180,
                      child: LiveKpiCard(
                        label: 'Est. spend',
                        value: dash.estimatedCostUsd,
                        prevValue: prev(dash.prevEstimatedCostUsd),
                        formatFn: fmtUsd,
                        deltaLabel: deltaLabel,
                        isRefreshing: isRefreshing,
                        accentValue: true,
                      ),
                    ),
                    if (dash.budgetUsd != null &&
                        dash.budgetUsedFraction != null) ...[
                      SizedBox(
                        width: 180,
                        child: LiveKpiCard(
                          label: 'Budget used',
                          value: dash.budgetUsedFraction!,
                          formatFn: (v) => '${(v * 100).toStringAsFixed(0)}%',
                          footnote: 'of ${fmtUsd(dash.budgetUsd!)} budget',
                          showLiveBadge: false,
                          valueColor: _budgetColor(dash.budgetUsedFraction!),
                          topBorderColor: _budgetColor(
                            dash.budgetUsedFraction!,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(
                      width: 180,
                      child: LiveKpiCard(
                        label: 'Cost / task',
                        value: costPerTask,
                        prevValue: prev(prevCostPerTask),
                        formatFn: fmtUsd,
                        deltaLabel: deltaLabel,
                        isRefreshing: isRefreshing,
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: LiveKpiCard(
                        label: 'Cost / 1M tok',
                        value: costPer1MTokens,
                        prevValue: prev(prevCostPer1MTokens),
                        formatFn: fmtUsd,
                        deltaLabel: deltaLabel,
                        isRefreshing: isRefreshing,
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child:
                          topCostModel == null ||
                              topCostModel.estimatedCostUsd <= 0
                          ? KpiCard(label: 'Top model', value: '—')
                          : KpiCard(
                              label: 'Top model',
                              value:
                                  '${fmtUsd(topCostModel.estimatedCostUsd)}\n${topCostModel.model}',
                            ),
                    ),
                  ],
                ),
              ),
              if (dash.topRetryTasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                CursorPanel(
                  title: 'Needs attention',
                  subtitle: 'Highest retry counts right now',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final t in dash.topRetryTasks.take(5))
                        _TopRetryTaskRow(
                          task: t,
                          onTap: widget.onOpenTask == null
                              ? null
                              : () => widget.onOpenTask!(t.id),
                        ),
                    ],
                  ),
                ),
              ],
              if (dash.periodComparisons.isNotEmpty) ...[
                const SizedBox(height: 12),
                CursorPanel(
                  title: 'Trends',
                  subtitle: 'Fixed comparisons, independent of the selected range',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final c in dash.periodComparisons)
                        _PeriodComparisonRow(comparison: c),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              CursorPanel(
                title: 'Live Charts',
                actions: [
                  Text(
                    'refreshed ${_lastRefresh.hour.toString().padLeft(2, '0')}:${_lastRefresh.minute.toString().padLeft(2, '0')}:${_lastRefresh.second.toString().padLeft(2, '0')}',
                    style: TextStyle(color: AppTheme.muted, fontSize: 9),
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChartCard(
                      title: 'Retries & tasks over time',
                      height: 240,
                      child: Column(
                        children: [
                          Expanded(
                            child: RetryTrendChart(
                              trend: dash.retryTrend,
                              nowLineX: dash.retryTrend.isNotEmpty
                                  ? dash.retryTrend.length.toDouble() -
                                        1 +
                                        _nowLineOffset
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _LegendDot(
                                color: kRetriesSeriesColor,
                                label: 'Retries',
                              ),
                              const SizedBox(width: 16),
                              _LegendDot(
                                color: kTasksSeriesColor,
                                label: 'Tasks',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ChartCard(
                            title: 'Tasks by source tool',
                            child: ToolUsageChart(tools: dash.byTool),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ChartCard(
                            title: 'Task status',
                            height: 220,
                            child: TaskStatusChart(
                              active: dash.activeCount,
                              completed: dash.completedCount,
                              abandoned: dash.abandonedCount,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ChartCard(
                            title: 'Agentic event types',
                            child: EventTypeChart(events: dash.byEventType),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ChartCard(
                            title: 'Token usage by model',
                            legend: [
                              _LegendDot(
                                color: kTokenInputColor,
                                label: 'Input',
                              ),
                              _LegendDot(
                                color: kTokenOutputColor,
                                label: 'Output',
                              ),
                            ],
                            child: TokenUsageChart(models: dash.byModel),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ChartCard(
                            title: 'Events by hour of day',
                            child: HourlyActivityChart(
                              hourlyData: dash.hourlyActivity,
                              nowLineHour: _nowHour,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ChartCard(
                            title: 'Daily completion rate',
                            legend: [
                              _LegendDot(
                                color: kCompletedColor,
                                label: 'Completed',
                              ),
                              _LegendDot(
                                color: kAbandonedColor,
                                label: 'Abandoned',
                              ),
                            ],
                            child: DailyCompletionTrendChart(
                              dailyData: dash.dailyCompletionRate,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CursorPanel(
                            title: 'By source tool',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...dash.byTool
                                    .take(6)
                                    .map(
                                      (t) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          children: [
                                            ToolIcon(t.sourceTool, size: 12),
                                            const SizedBox(width: 6),
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                t.sourceTool,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.fg,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: maxTool > 0
                                                      ? t.count / maxTool
                                                      : 0.0,
                                                  minHeight: 8,
                                                  backgroundColor:
                                                      AppTheme.base2,
                                                  color: AppTheme.accent,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            SizedBox(
                                              width: 36,
                                              child: Text(
                                                '${t.count}',
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  color: AppTheme.muted,
                                                  fontSize: 11,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                if (dash.byTool.isEmpty)
                                  const Text(
                                    'No tasks yet',
                                    style: TextStyle(color: AppTheme.muted),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CursorPanel(
                            title: 'LLM models',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSm,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 16,
                                  dataRowMinHeight: 28,
                                  dataRowMaxHeight: 32,
                                  headingRowHeight: 32,
                                  headingTextStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.fg,
                                  ),
                                  dataTextStyle: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.fg,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('Model')),
                                    DataColumn(
                                      label: Text('Tokens'),
                                      numeric: true,
                                    ),
                                    DataColumn(
                                      label: Text('Cost'),
                                      numeric: true,
                                    ),
                                    DataColumn(
                                      label: Text('Events'),
                                      numeric: true,
                                    ),
                                  ],
                                  rows: dash.byModel
                                      .take(8)
                                      .map(
                                        (m) => DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                m.model,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                fmtNum(
                                                  m.inputTokens +
                                                      m.outputTokens,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                '~\$${m.estimatedCostUsd.toStringAsFixed(3)}',
                                              ),
                                            ),
                                            DataCell(Text('${m.events}')),
                                          ],
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Local models highlight section
                    ..._buildLocalModelsSection(dash.byModel),
                    const SizedBox(height: 16),
                    ChartCard(
                      title: 'Task duration',
                      child: TaskDurationHistogram(
                        buckets: dash.durationDistribution,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CursorPanel(
                      title: 'Model retry rates',
                      child: SizedBox(
                        height: 200,
                        child: ModelRetryChart(models: dash.byModelRetryRate),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ChartCard(
                            title: 'Agent comparison',
                            child: AgentComparisonChart(agents: dash.byAgent),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ChartCard(
                            title: 'Repo activity',
                            child: RepoActivityChart(repos: dash.byRepo),
                          ),
                        ),
                      ],
                    ),
                    if (dash.agentHealth.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      CursorPanel(
                        title: 'Agent health',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final health in dash.agentHealth)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        health.agentName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.fg,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Last seen: ${fmtTs(health.lastHeartbeatAt)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${health.activeTasks} active',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    StatusChip(
                                      label: health.stale ? 'Stale' : 'Active',
                                      color: health.stale
                                          ? AppTheme.danger
                                          : AppTheme.success,
                                      pulse: !health.stale,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds a highlighted section for locally-running models (Ollama, LM Studio, etc.)
  /// Returns an empty list when no local models are detected.
  List<Widget> _buildLocalModelsSection(List<ModelStat> allModels) {
    final localModels = allModels.where((m) => isLocalModel(m.model)).toList();
    if (localModels.isEmpty) return [];

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CursorPanel(
              title: 'Local LLMs',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${localModels.length} model${localModels.length == 1 ? '' : 's'} detected',
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'total tok: ${fmtNum(localModels.fold<int>(0, (s, m) => s + m.inputTokens + m.outputTokens))}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...localModels.map(
                    (m) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m.model,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.fg,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'tok=${fmtNum(m.inputTokens + m.outputTokens)}',
                            style: const TextStyle(
                              color: AppTheme.success,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

/// Green under 70% of budget, amber up to 100%, red once over.
Color _budgetColor(double usedFraction) {
  if (usedFraction >= 1.0) return AppTheme.danger;
  if (usedFraction >= 0.7) return AppTheme.warn;
  return AppTheme.success;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: AppTheme.muted, fontSize: 11)),
      ],
    );
  }
}

class _TopRetryTaskRow extends StatelessWidget {
  const _TopRetryTaskRow({required this.task, this.onTap});

  final TopRetryTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final brandColor = ToolBrand.colorFor(task.sourceTool);
    final severe = task.retryCount >= 8;
    final chipColor = severe ? AppTheme.danger : AppTheme.warn;
    final title = task.title?.trim();
    final label = (title != null && title.isNotEmpty)
        ? title
        : TaskSummary.formatTaskId(task.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brandColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ToolIcon(task.sourceTool, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.instrumentSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.fg,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      ToolBrand.forTool(task.sourceTool).name,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${task.retryCount} ${task.retryCount == 1 ? 'retry' : 'retries'}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: chipColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodComparisonRow extends StatelessWidget {
  const _PeriodComparisonRow({required this.comparison});

  final PeriodComparison comparison;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              comparison.label,
              style: GoogleFonts.instrumentSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.fg,
              ),
            ),
          ),
          Expanded(
            child: _PeriodMetric(
              label: 'Retries',
              current: comparison.current.totalRetries.toDouble(),
              previous: comparison.previous.totalRetries.toDouble(),
              format: (v) => v.toStringAsFixed(0),
            ),
          ),
          Expanded(
            child: _PeriodMetric(
              label: 'Spend',
              current: comparison.current.estimatedCostUsd,
              previous: comparison.previous.estimatedCostUsd,
              format: fmtUsd,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodMetric extends StatelessWidget {
  const _PeriodMetric({
    required this.label,
    required this.current,
    required this.previous,
    required this.format,
  });

  final String label;
  final double current;
  final double previous;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final delta = fmtDelta(current, previous);
    final deltaUp = delta != null && !delta.startsWith('-');
    final deltaColor = delta == null
        ? AppTheme.muted
        : (deltaUp ? AppTheme.danger : AppTheme.success);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              '${format(previous)} → ${format(current)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: AppTheme.fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (delta != null) ...[
              const SizedBox(width: 6),
              Text(
                delta,
                style: TextStyle(
                  color: deltaColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.base2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              size: 16,
              color: AppTheme.muted,
            ),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(minimumSize: const Size(28, 28)),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.fg)),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppTheme.muted,
            ),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(minimumSize: const Size(28, 28)),
          ),
        ],
      ),
    );
  }
}
