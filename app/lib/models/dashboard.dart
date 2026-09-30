enum DashboardRange { all, h24, d7, d30 }

class DashboardFilters {
  const DashboardFilters({
    this.from,
    this.to,
    this.sourceTool,
    this.agentId,
    this.model,
    this.range = DashboardRange.all,
  });

  final String? from;
  final String? to;
  final String? sourceTool;
  final String? agentId;
  final String? model;
  final DashboardRange range;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (from != null) params['from'] = from!;
    if (to != null) params['to'] = to!;
    if (sourceTool != null) params['sourceTool'] = sourceTool!;
    if (agentId != null) params['agentId'] = agentId!;
    if (model != null) params['model'] = model!;
    return params;
  }

  DashboardFilters copyWith({
    String? from,
    String? to,
    String? sourceTool,
    String? agentId,
    String? model,
    DashboardRange? range,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearSourceTool = false,
    bool clearAgentId = false,
    bool clearModel = false,
  }) {
    return DashboardFilters(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      sourceTool: clearSourceTool ? null : (sourceTool ?? this.sourceTool),
      agentId: clearAgentId ? null : (agentId ?? this.agentId),
      model: clearModel ? null : (model ?? this.model),
      range: range ?? this.range,
    );
  }

  /// Builds API query filters from [range] and optional tool/model/agent selections.
  DashboardFilters forQuery({
    List<String>? availableTools,
    List<String>? availableModels,
    List<AgentRef>? availableAgents,
  }) {
    String? computedFrom;
    final now = DateTime.now();
    switch (range) {
      case DashboardRange.all:
        computedFrom = null;
      case DashboardRange.h24:
        computedFrom = now
            .subtract(const Duration(hours: 24))
            .toUtc()
            .toIso8601String();
      case DashboardRange.d7:
        computedFrom = now
            .subtract(const Duration(days: 7))
            .toUtc()
            .toIso8601String();
      case DashboardRange.d30:
        computedFrom = now
            .subtract(const Duration(days: 30))
            .toUtc()
            .toIso8601String();
    }

    return DashboardFilters(
      from: computedFrom,
      to: to,
      sourceTool: sourceTool,
      agentId: agentId,
      model: model,
      range: range,
    );
  }

  static const rangeLabels = ['all', '24h', '7d', '30d'];

  String get rangeLabel => rangeLabels[range.index];

  /// Whether the selected range supports period-over-period deltas.
  bool get hasComparisonPeriod => range != DashboardRange.all;

  /// Label shown under KPI cards for delta comparison.
  String get comparisonDeltaLabel => switch (range) {
    DashboardRange.h24 => 'vs prev 24h',
    DashboardRange.d7 => 'vs prev 7d',
    DashboardRange.d30 => 'vs prev 30d',
    DashboardRange.all => '',
  };
}

class ToolStat {
  const ToolStat({
    required this.sourceTool,
    required this.count,
    this.retries = 0,
  });

  final String sourceTool;
  final int count;
  final int retries;

  factory ToolStat.fromJson(Map<String, dynamic> json) {
    return ToolStat(
      sourceTool: json['sourceTool'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      retries: json['retries'] as int? ?? 0,
    );
  }
}

class EventTypeStat {
  const EventTypeStat({required this.eventType, required this.count});

  final String eventType;
  final int count;

  factory EventTypeStat.fromJson(Map<String, dynamic> json) {
    return EventTypeStat(
      eventType: json['eventType'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }
}

class ModelStat {
  const ModelStat({
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.events,
    required this.estimatedCostUsd,
  });

  final String model;
  final int inputTokens;
  final int outputTokens;
  final int events;
  final double estimatedCostUsd;

  factory ModelStat.fromJson(Map<String, dynamic> json) {
    return ModelStat(
      model: json['model'] as String? ?? '',
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      events: json['events'] as int? ?? 0,
      estimatedCostUsd: (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RetryTrendPoint {
  const RetryTrendPoint({
    required this.day,
    required this.retries,
    required this.tasks,
  });

  final String day;
  final int retries;
  final int tasks;

  factory RetryTrendPoint.fromJson(Map<String, dynamic> json) {
    return RetryTrendPoint(
      day: json['day'] as String? ?? '',
      retries: json['retries'] as int? ?? 0,
      tasks: json['tasks'] as int? ?? 0,
    );
  }
}

class TopRetryTask {
  const TopRetryTask({
    required this.id,
    required this.sourceTool,
    required this.retryCount,
    required this.status,
    this.title,
    this.startedAt,
  });

  final String id;
  final String sourceTool;
  final int retryCount;
  final String status;
  final String? title;
  final String? startedAt;

  factory TopRetryTask.fromJson(Map<String, dynamic> json) {
    return TopRetryTask(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      sourceTool: json['sourceTool'] as String? ?? '',
      retryCount: json['retryCount'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      startedAt: json['startedAt'] as String?,
    );
  }
}

class AgentRef {
  const AgentRef({required this.id, required this.name});

  final String id;
  final String name;

  factory AgentRef.fromJson(Map<String, dynamic> json) {
    return AgentRef(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

class AgentSummary {
  const AgentSummary({
    required this.agentId,
    required this.agentName,
    required this.taskCount,
    required this.retryCount,
    required this.inputTokens,
    required this.outputTokens,
    required this.avgDurationSec,
  });

  final String agentId;
  final String agentName;
  final int taskCount;
  final int retryCount;
  final int inputTokens;
  final int outputTokens;
  final double avgDurationSec;

  factory AgentSummary.fromJson(Map<String, dynamic> json) {
    return AgentSummary(
      agentId: json['agentId'] as String? ?? '',
      agentName: json['agentName'] as String? ?? '',
      taskCount: json['taskCount'] as int? ?? 0,
      retryCount: json['retryCount'] as int? ?? 0,
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      avgDurationSec: (json['avgDurationSec'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RepoStat {
  const RepoStat({
    required this.repoName,
    required this.taskCount,
    required this.retryCount,
    required this.completedCount,
    required this.totalCount,
    required this.completionRate,
  });

  final String repoName;
  final int taskCount;
  final int retryCount;
  final int completedCount;
  final int totalCount;
  final double completionRate;

  factory RepoStat.fromJson(Map<String, dynamic> json) {
    final totalCount =
        json['totalCount'] as int? ?? json['total_count'] as int? ?? 0;
    final completedCount =
        json['completedCount'] as int? ?? json['completed_count'] as int? ?? 0;
    return RepoStat(
      repoName:
          json['repoName'] as String? ??
          json['repo_name'] as String? ??
          '(unknown)',
      taskCount: json['taskCount'] as int? ?? 0,
      retryCount: json['retryCount'] as int? ?? 0,
      completedCount: completedCount,
      totalCount: totalCount,
      completionRate: totalCount > 0 ? completedCount / totalCount : 0,
    );
  }
}

class DurationBucket {
  const DurationBucket({required this.bucket, required this.count});

  final String bucket;
  final int count;

  factory DurationBucket.fromJson(Map<String, dynamic> json) {
    return DurationBucket(
      bucket: json['bucket'] as String? ?? '',
      count: json['count'] as int? ?? 0,
    );
  }
}

class DailyCompletion {
  const DailyCompletion({
    required this.day,
    required this.completed,
    required this.abandoned,
    required this.total,
  });

  final String day;
  final int completed;
  final int abandoned;
  final int total;

  factory DailyCompletion.fromJson(Map<String, dynamic> json) {
    return DailyCompletion(
      day: json['day'] as String? ?? '',
      completed: json['completed'] as int? ?? 0,
      abandoned: json['abandoned'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }
}

class HourlyActivity {
  const HourlyActivity({required this.hour, required this.count});

  final int hour;
  final int count;

  factory HourlyActivity.fromJson(Map<String, dynamic> json) {
    return HourlyActivity(
      hour: json['hour'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
    );
  }
}

class ModelRetryStat {
  const ModelRetryStat({
    required this.model,
    required this.totalTasks,
    required this.totalRetries,
    required this.retryRate,
  });

  final String model;
  final int totalTasks;
  final int totalRetries;
  final double retryRate;

  factory ModelRetryStat.fromJson(Map<String, dynamic> json) {
    return ModelRetryStat(
      model: json['model'] as String? ?? '',
      totalTasks:
          json['totalTasks'] as int? ?? json['total_tasks'] as int? ?? 0,
      totalRetries:
          json['totalRetries'] as int? ?? json['total_retries'] as int? ?? 0,
      retryRate:
          (json['retryRate'] as num?)?.toDouble() ??
          json['retry_rate'] as double? ??
          0,
    );
  }
}

class AgentHealth {
  const AgentHealth({
    required this.agentId,
    required this.agentName,
    this.lastHeartbeatAt,
    required this.stale,
    required this.totalSessions,
    required this.activeTasks,
  });

  final String agentId;
  final String agentName;
  final String? lastHeartbeatAt;
  final bool stale;
  final int totalSessions;
  final int activeTasks;

  factory AgentHealth.fromJson(Map<String, dynamic> json) {
    return AgentHealth(
      agentId: json['agentId'] as String? ?? '',
      agentName: json['agentName'] as String? ?? '',
      lastHeartbeatAt: json['lastHeartbeatAt'] as String?,
      stale: json['stale'] as bool? ?? false,
      totalSessions: json['totalSessions'] as int? ?? 0,
      activeTasks: json['activeTasks'] as int? ?? 0,
    );
  }
}

class AgenticDashboard {
  const AgenticDashboard({
    required this.taskCount,
    required this.activeCount,
    required this.completedCount,
    required this.abandonedCount,
    required this.completionRate,
    required this.abandonRate,
    required this.totalRetries,
    required this.avgRetries,
    required this.retryRate,
    required this.inputTokens,
    required this.outputTokens,
    required this.agentCount,
    required this.avgSessionMinutes,
    required this.sessionStarts,
    required this.sessionEnds,
    required this.subagentEvents,
    required this.compactionEvents,
    required this.byTool,
    required this.byEventType,
    required this.byModel,
    required this.retryTrend,
    required this.topRetryTasks,
    required this.availableTools,
    required this.availableModels,
    required this.availableAgents,
    required this.byAgent,
    required this.byRepo,
    required this.durationDistribution,
    required this.dailyCompletionRate,
    required this.hourlyActivity,
    required this.byModelRetryRate,
    required this.agentHealth,
    required this.prevTaskCount,
    required this.prevTotalRetries,
    required this.prevActiveCount,
    required this.prevCompletedCount,
    required this.prevAbandonedCount,
    required this.prevInputTokens,
    required this.prevOutputTokens,
    required this.prevAvgRetries,
    required this.prevRetryRate,
    required this.prevAgentCount,
    required this.prevAvgSessionMinutes,
    required this.estimatedCostUsd,
    required this.prevEstimatedCostUsd,
    this.budgetUsd,
    this.budgetUsedFraction,
    this.periodComparisons = const [],
  });

  final int taskCount;
  final int activeCount;
  final int completedCount;
  final int abandonedCount;
  final double completionRate;
  final double abandonRate;
  final int totalRetries;
  final double avgRetries;
  final double retryRate;
  final int inputTokens;
  final int outputTokens;
  final int agentCount;
  final double avgSessionMinutes;
  final int sessionStarts;
  final int sessionEnds;
  final int subagentEvents;
  final int compactionEvents;
  final List<ToolStat> byTool;
  final List<EventTypeStat> byEventType;
  final List<ModelStat> byModel;
  final List<RetryTrendPoint> retryTrend;
  final List<TopRetryTask> topRetryTasks;
  final List<String> availableTools;
  final List<String> availableModels;
  final List<AgentRef> availableAgents;
  final List<AgentSummary> byAgent;
  final List<RepoStat> byRepo;
  final List<DurationBucket> durationDistribution;
  final List<DailyCompletion> dailyCompletionRate;
  final List<HourlyActivity> hourlyActivity;
  final List<ModelRetryStat> byModelRetryRate;
  final List<AgentHealth> agentHealth;
  final int prevTaskCount;
  final int prevTotalRetries;
  final int prevActiveCount;
  final int prevCompletedCount;
  final int prevAbandonedCount;
  final int prevInputTokens;
  final int prevOutputTokens;
  final double prevAvgRetries;
  final double prevRetryRate;
  final int prevAgentCount;
  final double prevAvgSessionMinutes;
  final double estimatedCostUsd;
  final double prevEstimatedCostUsd;

  /// Configured spend ceiling for the period, if the user has set one.
  final double? budgetUsd;

  /// `estimatedCostUsd / budgetUsd`, or null when no budget is configured.
  final double? budgetUsedFraction;

  /// Fixed week-over-week and month-over-month comparisons, independent of
  /// whichever date range is currently selected.
  final List<PeriodComparison> periodComparisons;

  factory AgenticDashboard.fromJson(Map<String, dynamic> json) {
    return AgenticDashboard(
      taskCount: json['taskCount'] as int? ?? 0,
      activeCount: json['activeCount'] as int? ?? 0,
      completedCount: json['completedCount'] as int? ?? 0,
      abandonedCount: json['abandonedCount'] as int? ?? 0,
      completionRate: (json['completionRate'] as num?)?.toDouble() ?? 0,
      abandonRate: (json['abandonRate'] as num?)?.toDouble() ?? 0,
      totalRetries: json['totalRetries'] as int? ?? 0,
      avgRetries: (json['avgRetries'] as num?)?.toDouble() ?? 0,
      retryRate: (json['retryRate'] as num?)?.toDouble() ?? 0,
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      agentCount: json['agentCount'] as int? ?? 0,
      avgSessionMinutes: (json['avgSessionMinutes'] as num?)?.toDouble() ?? 0,
      sessionStarts: json['sessionStarts'] as int? ?? 0,
      sessionEnds: json['sessionEnds'] as int? ?? 0,
      subagentEvents: json['subagentEvents'] as int? ?? 0,
      compactionEvents: json['compactionEvents'] as int? ?? 0,
      byTool: (json['byTool'] as List<dynamic>? ?? [])
          .map((e) => ToolStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      byEventType: (json['byEventType'] as List<dynamic>? ?? [])
          .map((e) => EventTypeStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      byModel: (json['byModel'] as List<dynamic>? ?? [])
          .map((e) => ModelStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      retryTrend: (json['retryTrend'] as List<dynamic>? ?? [])
          .map((e) => RetryTrendPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      topRetryTasks: (json['topRetryTasks'] as List<dynamic>? ?? [])
          .map((e) => TopRetryTask.fromJson(e as Map<String, dynamic>))
          .toList(),
      availableTools: (json['availableTools'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      availableModels: (json['availableModels'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      availableAgents: (json['availableAgents'] as List<dynamic>? ?? [])
          .map((e) => AgentRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      byAgent: (json['byAgent'] as List<dynamic>? ?? [])
          .map((e) => AgentSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      byRepo: (json['byRepo'] as List<dynamic>? ?? [])
          .map((e) => RepoStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      durationDistribution:
          (json['durationDistribution'] as List<dynamic>? ?? [])
              .map((e) => DurationBucket.fromJson(e as Map<String, dynamic>))
              .toList(),
      dailyCompletionRate: (json['dailyCompletionRate'] as List<dynamic>? ?? [])
          .map((e) => DailyCompletion.fromJson(e as Map<String, dynamic>))
          .toList(),
      hourlyActivity: (json['hourlyActivity'] as List<dynamic>? ?? [])
          .map((e) => HourlyActivity.fromJson(e as Map<String, dynamic>))
          .toList(),
      byModelRetryRate: (json['byModelRetryRate'] as List<dynamic>? ?? [])
          .map((e) => ModelRetryStat.fromJson(e as Map<String, dynamic>))
          .toList(),
      agentHealth: (json['agentHealth'] as List<dynamic>? ?? [])
          .map((e) => AgentHealth.fromJson(e as Map<String, dynamic>))
          .toList(),
      prevTaskCount: json['prevTaskCount'] as int? ?? 0,
      prevTotalRetries: json['prevTotalRetries'] as int? ?? 0,
      prevActiveCount: json['prevActiveCount'] as int? ?? 0,
      prevCompletedCount: json['prevCompletedCount'] as int? ?? 0,
      prevAbandonedCount: json['prevAbandonedCount'] as int? ?? 0,
      prevInputTokens: json['prevInputTokens'] as int? ?? 0,
      prevOutputTokens: json['prevOutputTokens'] as int? ?? 0,
      prevAvgRetries: (json['prevAvgRetries'] as num?)?.toDouble() ?? 0,
      prevRetryRate: (json['prevRetryRate'] as num?)?.toDouble() ?? 0,
      prevAgentCount: json['prevAgentCount'] as int? ?? 0,
      prevAvgSessionMinutes:
          (json['prevAvgSessionMinutes'] as num?)?.toDouble() ?? 0,
      estimatedCostUsd: (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0,
      prevEstimatedCostUsd:
          (json['prevEstimatedCostUsd'] as num?)?.toDouble() ?? 0,
      budgetUsd: (json['budgetUsd'] as num?)?.toDouble(),
      budgetUsedFraction: (json['budgetUsedFraction'] as num?)?.toDouble(),
      periodComparisons: (json['periodComparisons'] as List<dynamic>? ?? [])
          .map((e) => PeriodComparison.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PeriodTotals {
  const PeriodTotals({
    required this.taskCount,
    required this.totalRetries,
    required this.retryRate,
    required this.estimatedCostUsd,
  });

  final int taskCount;
  final int totalRetries;
  final double retryRate;
  final double estimatedCostUsd;

  factory PeriodTotals.fromJson(Map<String, dynamic> json) {
    return PeriodTotals(
      taskCount: json['taskCount'] as int? ?? 0,
      totalRetries: json['totalRetries'] as int? ?? 0,
      retryRate: (json['retryRate'] as num?)?.toDouble() ?? 0,
      estimatedCostUsd: (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PeriodComparison {
  const PeriodComparison({
    required this.label,
    required this.current,
    required this.previous,
  });

  final String label;
  final PeriodTotals current;
  final PeriodTotals previous;

  factory PeriodComparison.fromJson(Map<String, dynamic> json) {
    return PeriodComparison(
      label: json['label'] as String? ?? '',
      current: PeriodTotals.fromJson(
        json['current'] as Map<String, dynamic>? ?? const {},
      ),
      previous: PeriodTotals.fromJson(
        json['previous'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class McpConfig {
  const McpConfig({
    required this.endpointHint,
    required this.command,
    required this.args,
    required this.configJson,
    this.transport = 'stdio',
  });

  final String endpointHint;
  final String command;
  final List<String> args;
  final String configJson;
  final String transport;

  factory McpConfig.fromJson(Map<String, dynamic> json) {
    return McpConfig(
      endpointHint: json['endpointHint'] as String? ?? '',
      command: json['command'] as String? ?? '',
      args:
          (json['args'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      configJson: json['configJson'] as String? ?? '',
      transport: json['transport'] as String? ?? 'stdio',
    );
  }
}

class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.service,
    required this.collectors,
  });

  final String status;
  final String service;
  final bool collectors;

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      status: json['status'] as String? ?? 'unknown',
      service: json['service'] as String? ?? '',
      collectors: json['collectors'] as bool? ?? false,
    );
  }

  bool get isOk => status == 'ok';
}
