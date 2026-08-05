import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/charts/session_waterfall.dart';
import '../widgets/common_widgets.dart';
import '../widgets/cursor_shell.dart';
import '../widgets/tool_icon.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({
    super.key,
    this.selectedTaskId,
    this.onSelectTask,
    this.onClearTask,
  });

  final String? selectedTaskId;
  final void Function(String id)? onSelectTask;
  final VoidCallback? onClearTask;

  static const _pageSize = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selectedTaskId != null) {
      return _TaskDetailView(taskId: selectedTaskId!, onBack: onClearTask);
    }

    final filters = ref.watch(dashboardFiltersProvider);
    final page = ref.watch(tasksPageProvider);
    final tasksAsync = ref.watch(tasksProvider(filters));

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LoadingError(
        error: e,
        onRetry: () => ref.invalidate(tasksProvider(filters)),
      ),
      data: (response) {
        if (response.items.isEmpty) {
          return const Center(
            child: Text(
              'No tasks. Start coding with Cursor/Claude or run npm run seed.',
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          );
        }

        final totalPages = (response.totalCount / _pageSize).ceil().clamp(
          1,
          999999,
        );
        final currentPage = page.clamp(0, totalPages - 1);

        return Column(
          children: [
            if (response.totalCount > _pageSize)
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Page ${currentPage + 1} of $totalPages · ${response.totalCount} tasks',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      onPressed: currentPage > 0
                          ? () => ref.read(tasksPageProvider.notifier).state =
                                currentPage - 1
                          : null,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: currentPage < totalPages - 1
                          ? () => ref.read(tasksPageProvider.notifier).state =
                                currentPage + 1
                          : null,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: response.items.length,
                itemBuilder: (context, i) {
                  final t = response.items[i];
                  return CursorListTile(
                    leading: SizedBox(
                      width: 20,
                      child: Text(
                        '${currentPage * _pageSize + i + 1}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    title: Text(
                      t.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Row(
                      children: [
                        ToolIcon(t.sourceTool, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          t.sourceTool,
                          style: TextStyle(
                            color: ToolBrand.colorFor(t.sourceTool),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' · retries ${t.retryCount} · ${t.status}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppTheme.muted,
                    ),
                    onTap: () => onSelectTask?.call(t.id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskDetailView extends ConsumerWidget {
  const _TaskDetailView({required this.taskId, this.onBack});

  final String taskId;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(taskDetailProvider(taskId));

    return detailAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LoadingError(
        error: e,
        onRetry: () => ref.invalidate(taskDetailProvider(taskId)),
      ),
      data: (task) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 35,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: AppTheme.base3,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    tooltip: 'Back to tasks',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(28, 28),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.fg),
                    ),
                  ),
                  ToolIcon(task.sourceTool, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    task.sourceTool,
                    style: TextStyle(
                      fontSize: 11,
                      color: ToolBrand.colorFor(task.sourceTool),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ' · ${task.status} · r=${task.retryCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  CursorPanel(
                    title: 'Task info',
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        _MetaChip(label: 'Status', value: task.status),
                        _MetaChip(
                          label: 'Retries',
                          value: '${task.retryCount}',
                        ),
                        _MetaChip(
                          label: 'Input tokens',
                          value: '${task.inputTokens}',
                        ),
                        _MetaChip(
                          label: 'Output tokens',
                          value: '${task.outputTokens}',
                        ),
                        if (task.projectRoot != null)
                          _MetaChip(label: 'Project', value: task.projectRoot!),
                        if (task.repoName != null)
                          _MetaChip(label: 'Repo', value: task.repoName!),
                        if (task.gitBranch != null)
                          _MetaChip(label: 'Branch', value: task.gitBranch!),
                        if (task.startedAt != null)
                          _MetaChip(
                            label: 'Started',
                            value: fmtTs(task.startedAt),
                          ),
                        if (task.endedAt != null)
                          _MetaChip(label: 'Ended', value: fmtTs(task.endedAt)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (task.timeline.isNotEmpty) ...[
                    CursorPanel(
                      title: 'Session waterfall',
                      child: SessionWaterfallChart(timeline: task.timeline),
                    ),
                    const SizedBox(height: 12),
                    CursorPanel(
                      title: 'Event timeline',
                      child: Column(
                        children: task.timeline.map((e) {
                          final modDetail = e.modificationDetail;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: GestureDetector(
                              onTap: () => _showChangePopup(context, e),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    e.isRetrySignal
                                        ? Icons.circle
                                        : Icons.circle_outlined,
                                    size: 8,
                                    color: e.isRetrySignal
                                        ? AppTheme.danger
                                        : AppTheme.muted,
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      fmtTs(e.occurredAt),
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      e.eventType,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        color: e.isRetrySignal
                                            ? AppTheme.danger
                                            : AppTheme.accent,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.summary,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.fg,
                                          ),
                                        ),
                                        if (modDetail != e.summary &&
                                            modDetail.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 2,
                                            ),
                                            child: Text(
                                              modDetail,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: e.isRetrySignal
                                                    ? AppTheme.danger
                                                    : AppTheme.hover,
                                                fontStyle: FontStyle.italic,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: AppTheme.muted,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No events yet — task is still active or no telemetry was recorded.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

void _showChangePopup(BuildContext context, TaskTimelineEvent event) {
  final payload = event.payload;
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppTheme.base3,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: event.isRetrySignal
                    ? AppTheme.danger.withValues(alpha: 0.1)
                    : AppTheme.base2,
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Icon(
                    event.isRetrySignal
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    size: 16,
                    color: event.isRetrySignal
                        ? AppTheme.danger
                        : AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.eventType,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: event.isRetrySignal
                                ? AppTheme.danger
                                : AppTheme.accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          fmtTs(event.occurredAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.muted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(24, 24),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (event.summary.isNotEmpty) ...[
                    _PayloadField(label: 'Summary', value: event.summary),
                    const SizedBox(height: 12),
                  ],
                  if (payload.isEmpty)
                    const Text(
                      'No additional details available for this event.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12),
                    )
                  else
                    ...payload.entries.map((entry) {
                      final strValue = entry.value.toString();
                      final isLong = strValue.length > 120;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.muted,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (isLong)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.base2,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: SelectableText(
                                  strValue,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.fg,
                                    fontFamily: 'monospace',
                                    height: 1.4,
                                  ),
                                ),
                              )
                            else
                              SelectableText(
                                strValue,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.fg,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PayloadField extends StatelessWidget {
  const _PayloadField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isLong = value.length > 120;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        if (isLong)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.base2,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                value,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.fg,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          )
        else
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.fg,
              fontFamily: 'monospace',
            ),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.fg,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
