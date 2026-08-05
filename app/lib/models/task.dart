class TaskSummary {
  const TaskSummary({
    required this.id,
    required this.sourceTool,
    required this.status,
    required this.retryCount,
    this.title,
    this.startedAt,
    this.endedAt,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.repoName,
    this.gitBranch,
    this.projectRoot,
  });

  final String id;
  final String sourceTool;
  final String status;
  final int retryCount;
  final String? title;
  final String? startedAt;
  final String? endedAt;
  final int inputTokens;
  final int outputTokens;
  final String? repoName;
  final String? gitBranch;
  final String? projectRoot;

  /// User-facing label — prefers title, else id without the tool prefix.
  String get displayLabel {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return formatTaskId(id);
  }

  static String formatTaskId(String id) {
    final colon = id.indexOf(':');
    if (colon >= 0 && colon < id.length - 1) {
      final suffix = id.substring(colon + 1).trim();
      if (suffix.isNotEmpty) return suffix;
    }
    return id;
  }

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    return TaskSummary(
      id: json['id'] as String,
      sourceTool:
          json['source_tool'] as String? ?? json['sourceTool'] as String? ?? '',
      status: json['status'] as String? ?? 'ACTIVE',
      retryCount:
          json['retry_count'] as int? ?? json['retryCount'] as int? ?? 0,
      title: json['title'] as String?,
      startedAt: json['started_at'] as String? ?? json['startedAt'] as String?,
      endedAt: json['ended_at'] as String? ?? json['endedAt'] as String?,
      inputTokens:
          json['input_tokens'] as int? ?? json['inputTokens'] as int? ?? 0,
      outputTokens:
          json['output_tokens'] as int? ?? json['outputTokens'] as int? ?? 0,
      repoName: json['repo_name'] as String? ?? json['repoName'] as String?,
      gitBranch: json['git_branch'] as String? ?? json['gitBranch'] as String?,
      projectRoot:
          json['project_root'] as String? ?? json['projectRoot'] as String?,
    );
  }
}

class TaskListResponse {
  const TaskListResponse({required this.items, required this.totalCount});

  final List<TaskSummary> items;
  final int totalCount;

  factory TaskListResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .map((e) => TaskSummary.fromJson(e as Map<String, dynamic>))
        .toList();
    return TaskListResponse(
      items: items,
      totalCount:
          json['totalCount'] as int? ??
          json['total_count'] as int? ??
          items.length,
    );
  }
}

class TaskTimelineEvent {
  const TaskTimelineEvent({
    required this.eventType,
    required this.summary,
    required this.occurredAt,
    this.isRetrySignal = false,
    this.payload = const {},
  });

  final String eventType;
  final String summary;
  final String occurredAt;
  final bool isRetrySignal;
  final Map<String, dynamic> payload;

  factory TaskTimelineEvent.fromJson(Map<String, dynamic> json) {
    return TaskTimelineEvent(
      eventType:
          json['eventType'] as String? ?? json['event_type'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      occurredAt:
          json['occurredAt'] as String? ?? json['occurred_at'] as String? ?? '',
      isRetrySignal:
          json['isRetrySignal'] as bool? ??
          json['is_retry_signal'] as bool? ??
          false,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  /// Human-readable description of the modification this event represents.
  String get modificationDetail {
    if (eventType == 'EDIT') {
      final note = payload['note'] as String?;
      final file = payload['file'] as String?;
      final search = payload['search'] as String?;
      if (note != null && note.isNotEmpty) return note;
      if (file != null) return 'Modified $file';
      if (search != null) {
        return 'Edit: ${search.length > 60 ? '${search.substring(0, 60)}…' : search}';
      }
      return 'Code edit';
    }
    if (eventType == 'TEST_FAIL') {
      final test = payload['test'] as String?;
      final error = payload['error'] as String?;
      if (test != null) return 'Test failed: $test';
      if (error != null) {
        return 'Test error: ${error.length > 60 ? '${error.substring(0, 60)}…' : error}';
      }
      return 'Test failure';
    }
    if (eventType == 'DIFF_REJECTED') {
      final note = payload['note'] as String?;
      final error = payload['error'] as String?;
      if (note != null && note.isNotEmpty) return note;
      if (error != null) {
        return 'Rejected: ${error.length > 60 ? '${error.substring(0, 60)}…' : error}';
      }
      return 'Diff rejected';
    }
    if (eventType == 'COMPACTION') {
      final summary = payload['summary'] as String?;
      if (summary != null) {
        return 'Context compacted: ${summary.length > 60 ? '${summary.substring(0, 60)}…' : summary}';
      }
      return 'Context compaction';
    }
    if (eventType == 'TOKEN_USAGE') {
      final model = payload['model'] as String?;
      final input = payload['inputTokens'];
      final output = payload['outputTokens'];
      if (model != null) {
        return '$model: ${input ?? '?'} in / ${output ?? '?'} out';
      }
      return 'Token usage';
    }
    if (eventType == 'SUBAGENT') {
      final name = payload['name'] as String?;
      if (name != null) return 'Subagent: $name';
      return 'Subagent task';
    }
    if (eventType == 'TOOL_USAGE') {
      final cmds = payload['runCommands'];
      final files = payload['readFiles'];
      if (cmds != null || files != null) {
        return 'Ran $cmds commands, read $files files';
      }
      return 'Tool usage';
    }
    if (eventType == 'SESSION_START') {
      final query = payload['initialQuery'] as String?;
      if (query != null) {
        return 'Query: ${query.length > 60 ? '${query.substring(0, 60)}…' : query}';
      }
      return 'Session started';
    }
    return summary;
  }
}

class TaskDetail extends TaskSummary {
  const TaskDetail({
    required super.id,
    required super.sourceTool,
    required super.status,
    required super.retryCount,
    super.title,
    super.startedAt,
    super.endedAt,
    super.inputTokens,
    super.outputTokens,
    super.repoName,
    super.gitBranch,
    super.projectRoot,
    this.timeline = const [],
  });

  final List<TaskTimelineEvent> timeline;

  factory TaskDetail.fromJson(Map<String, dynamic> json) {
    final timeline = (json['timeline'] as List<dynamic>? ?? [])
        .map((e) => TaskTimelineEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return TaskDetail(
      id: json['id'] as String,
      sourceTool:
          json['source_tool'] as String? ?? json['sourceTool'] as String? ?? '',
      status: json['status'] as String? ?? 'ACTIVE',
      retryCount:
          json['retry_count'] as int? ?? json['retryCount'] as int? ?? 0,
      title: json['title'] as String?,
      startedAt: json['started_at'] as String? ?? json['startedAt'] as String?,
      endedAt: json['ended_at'] as String? ?? json['endedAt'] as String?,
      inputTokens:
          json['input_tokens'] as int? ?? json['inputTokens'] as int? ?? 0,
      outputTokens:
          json['output_tokens'] as int? ?? json['outputTokens'] as int? ?? 0,
      repoName: json['repo_name'] as String? ?? json['repoName'] as String?,
      gitBranch: json['git_branch'] as String? ?? json['gitBranch'] as String?,
      projectRoot:
          json['project_root'] as String? ?? json['projectRoot'] as String?,
      timeline: timeline,
    );
  }
}
