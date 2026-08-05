import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import 'chart_utils.dart';

/// Clear green/red used by the daily completion rate chart.
const kCompletedColor = kCompletedTaskColor;
const kAbandonedColor = kAbandonedTaskColor;

class RetryTrendChart extends StatelessWidget {
  const RetryTrendChart({super.key, required this.trend, this.nowLineX});

  final List<RetryTrendPoint> trend;
  final double? nowLineX;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return Center(
        child: Text('No trend data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final maxY = trend
        .map((p) => [p.retries, p.tasks].reduce((a, b) => a > b ? a : b))
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final ceiling = maxY <= 0 ? 1.0 : maxY * 1.15;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: ceiling,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (trend.length / 5).clamp(1, 999).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    shortDayLabel(trend[i].day),
                    style: TextStyle(color: AppTheme.muted, fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: nowLineX != null
            ? ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: nowLineX!,
                    color: AppTheme.accent.withValues(alpha: 0.6),
                    strokeWidth: 1.5,
                    dashArray: [4, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topCenter,
                      style: TextStyle(
                        color: AppTheme.accent.withValues(alpha: 0.8),
                        fontSize: 8,
                      ),
                      labelResolver: (_) => 'now',
                    ),
                  ),
                ],
              )
            : null,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: monitorLineTooltip(
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              if (i < 0 || i >= trend.length) return null;
              final p = trend[i];
              final label = s.barIndex == 0 ? 'Retries' : 'Tasks';
              return LineTooltipItem(
                '$label: ${s.y.toInt()}\n${p.day}',
                chartTooltipTextStyle,
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < trend.length; i++)
                FlSpot(i.toDouble(), trend[i].retries.toDouble()),
            ],
            isCurved: true,
            color: kRetriesSeriesColor,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: kRetriesSeriesColor.withValues(alpha: 0.12),
            ),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < trend.length; i++)
                FlSpot(i.toDouble(), trend[i].tasks.toDouble()),
            ],
            isCurved: true,
            color: kTasksSeriesColor,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.accent.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class ToolUsageChart extends StatelessWidget {
  const ToolUsageChart({super.key, required this.tools});

  final List<ToolStat> tools;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) {
      return Center(
        child: Text('No tasks yet', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final top = tools.take(6).toList();
    final maxY =
        top.map((t) => t.count).reduce((a, b) => a > b ? a : b).toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].sourceTool.length > 8
                    ? top[i].sourceTool.substring(0, 8)
                    : top[i].sourceTool;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${top[group.x.toInt()].sourceTool}\n${rod.toY.toInt()}',
              chartTooltipTextStyle,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].count.toDouble(),
                  color: AppTheme.accent,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class EventTypeChart extends StatelessWidget {
  const EventTypeChart({super.key, required this.events});

  final List<EventTypeStat> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Text('No events yet', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final top = events.take(8).toList();
    final maxY =
        top.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].eventType.length > 10
                    ? top[i].eventType.substring(0, 10)
                    : top[i].eventType;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${top[group.x.toInt()].eventType}\n${rod.toY.toInt()}',
              chartTooltipTextStyle,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].count.toDouble(),
                  color: eventTypeColor(top[i].eventType),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class TokenUsageChart extends StatelessWidget {
  const TokenUsageChart({super.key, required this.models});

  final List<ModelStat> models;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Center(
        child: Text(
          'No LLM token events yet',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }

    final top = models.take(6).toList();
    final maxY =
        top
            .map((m) => m.inputTokens + m.outputTokens)
            .reduce((a, b) => a > b ? a : b)
            .toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) {
                if (v >= 1000) {
                  return Text(
                    '${(v / 1000).toStringAsFixed(0)}k',
                    style: TextStyle(color: AppTheme.muted, fontSize: 10),
                  );
                }
                return Text(
                  v.toInt().toString(),
                  style: TextStyle(color: AppTheme.muted, fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].model.length > 10
                    ? top[i].model.substring(0, 10)
                    : top[i].model;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) {
              final m = top[group.x.toInt()];
              return BarTooltipItem(
                '${m.model}\nInput: ${m.inputTokens}\nOutput: ${m.outputTokens}',
                chartTooltipTextStyle,
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (top[i].inputTokens + top[i].outputTokens).toDouble(),
                  rodStackItems: [
                    BarChartRodStackItem(
                      0,
                      top[i].inputTokens.toDouble(),
                      kTokenInputColor,
                    ),
                    BarChartRodStackItem(
                      top[i].inputTokens.toDouble(),
                      (top[i].inputTokens + top[i].outputTokens).toDouble(),
                      kTokenOutputColor,
                    ),
                  ],
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AgentComparisonChart extends StatelessWidget {
  const AgentComparisonChart({super.key, required this.agents});

  final List<AgentSummary> agents;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) {
      return Center(
        child: Text('No agent data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final top = agents.take(6).toList();
    final maxY =
        top
            .map(
              (a) => [
                a.taskCount,
                a.retryCount,
                a.inputTokens + a.outputTokens,
              ].reduce((a, b) => a > b ? a : b),
            )
            .reduce((a, b) => a > b ? a : b)
            .toDouble() *
        1.2;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].agentName.length > 8
                    ? top[i].agentName.substring(0, 8)
                    : top[i].agentName;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].taskCount.toDouble(),
                  color: AppTheme.accent,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
                BarChartRodData(
                  toY: top[i].retryCount.toDouble(),
                  color: AppTheme.warn,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
                BarChartRodData(
                  toY: (top[i].inputTokens + top[i].outputTokens).toDouble(),
                  color: AppTheme.hover,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class RepoActivityChart extends StatelessWidget {
  const RepoActivityChart({super.key, required this.repos});

  final List<RepoStat> repos;

  @override
  Widget build(BuildContext context) {
    if (repos.isEmpty) {
      return Center(
        child: Text('No repo data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final top = repos.take(8).toList();
    final maxY =
        top.map((r) => r.taskCount).reduce((a, b) => a > b ? a : b).toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].repoName.length > 10
                    ? top[i].repoName.substring(0, 10)
                    : top[i].repoName;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].taskCount.toDouble(),
                  color: AppTheme.accent,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class TaskDurationHistogram extends StatelessWidget {
  const TaskDurationHistogram({super.key, required this.buckets});

  final List<DurationBucket> buckets;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return Center(
        child: Text(
          'No completed tasks',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }

    final maxY =
        buckets.map((b) => b.count).reduce((a, b) => a > b ? a : b).toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    buckets[i].bucket,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${buckets[group.x.toInt()].bucket}\n${rod.toY.toInt()}',
              chartTooltipTextStyle,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].count.toDouble(),
                  color: kDurationBarColor,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class DailyCompletionTrendChart extends StatelessWidget {
  const DailyCompletionTrendChart({super.key, required this.dailyData});

  final List<DailyCompletion> dailyData;

  @override
  Widget build(BuildContext context) {
    if (dailyData.isEmpty) {
      return Center(
        child: Text('No daily data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final maxY =
        dailyData
            .map((d) => d.completed + d.abandoned)
            .reduce((a, b) => a > b ? a : b)
            .toDouble() *
        1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: (dailyData.length / 5).clamp(1, 999).toDouble(),
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= dailyData.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    shortDayLabel(dailyData[i].day),
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) {
              final d = dailyData[group.x.toInt()];
              return BarTooltipItem(
                '${d.day}\nCompleted: ${d.completed}\nAbandoned: ${d.abandoned}',
                chartTooltipTextStyle,
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < dailyData.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: dailyData[i].completed.toDouble(),
                  rodStackItems: [
                    BarChartRodStackItem(
                      0,
                      dailyData[i].completed.toDouble(),
                      kCompletedColor,
                    ),
                    BarChartRodStackItem(
                      dailyData[i].completed.toDouble(),
                      (dailyData[i].completed + dailyData[i].abandoned)
                          .toDouble(),
                      kAbandonedColor,
                    ),
                  ],
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class HourlyActivityChart extends StatelessWidget {
  const HourlyActivityChart({
    super.key,
    required this.hourlyData,
    this.nowLineHour,
  });

  final List<HourlyActivity> hourlyData;
  final int? nowLineHour;

  @override
  Widget build(BuildContext context) {
    if (hourlyData.isEmpty) {
      return Center(
        child: Text('No event data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    // Fill in all 24 hours
    final hourMap = <int, int>{};
    for (final h in hourlyData) {
      hourMap[h.hour] = h.count;
    }
    final filled = List.generate(24, (i) => hourMap[i] ?? 0);
    final maxY = filled.reduce((a, b) => a > b ? a : b).toDouble() * 1.15;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 3,
              getTitlesWidget: (v, meta) {
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    '${v.toInt().toString().padLeft(2, '0')}h',
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${group.x.toInt().toString().padLeft(2, '0')}h\n${rod.toY.toInt()} events',
              chartTooltipTextStyle,
            ),
          ),
        ),
        extraLinesData: nowLineHour != null
            ? ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: nowLineHour!.toDouble(),
                    color: AppTheme.accent.withValues(alpha: 0.6),
                    strokeWidth: 1.5,
                    dashArray: [3, 3],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topCenter,
                      style: TextStyle(
                        color: AppTheme.accent.withValues(alpha: 0.8),
                        fontSize: 8,
                      ),
                      labelResolver: (_) => 'now',
                    ),
                  ),
                ],
              )
            : null,
        barGroups: [
          for (var i = 0; i < 24; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: filled[i].toDouble(),
                  color: AppTheme.accent.withValues(alpha: 0.85),
                  width: 10,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class ModelRetryChart extends StatelessWidget {
  const ModelRetryChart({super.key, required this.models});

  final List<ModelRetryStat> models;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Center(
        child: Text('No model data', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final top = models.take(8).toList();
    final maxY =
        top.map((m) => m.retryRate).reduce((a, b) => a > b ? a : b).toDouble() *
        1.2;

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY.clamp(0.1, 999),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, _) => Text(
                '${(v * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: AppTheme.muted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].model.length > 12
                    ? top[i].model.substring(0, 12)
                    : top[i].model;
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    label,
                    style: TextStyle(color: AppTheme.fg, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: monitorBarTooltip(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${top[group.x.toInt()].model}\n${(rod.toY * 100).toStringAsFixed(1)}%',
              chartTooltipTextStyle,
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top[i].retryRate.clamp(0, 100),
                  color: AppTheme.warn,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class TaskStatusChart extends StatelessWidget {
  const TaskStatusChart({
    super.key,
    required this.active,
    required this.completed,
    required this.abandoned,
  });

  final int active;
  final int completed;
  final int abandoned;

  @override
  Widget build(BuildContext context) {
    final total = active + completed + abandoned;
    if (total == 0) {
      return Center(
        child: Text('No tasks', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final sections = [
      if (active > 0)
        PieChartSectionData(
          value: active.toDouble(),
          color: kActiveTaskColor,
          title: 'Active\n$active',
          radius: 56,
          titleStyle: TextStyle(
            color: AppTheme.textHeading,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      if (completed > 0)
        PieChartSectionData(
          value: completed.toDouble(),
          color: kCompletedTaskColor,
          title: 'Done\n$completed',
          radius: 56,
          titleStyle: TextStyle(
            color: AppTheme.textHeading,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      if (abandoned > 0)
        PieChartSectionData(
          value: abandoned.toDouble(),
          color: kAbandonedTaskColor,
          title: 'Aband.\n$abandoned',
          radius: 56,
          titleStyle: TextStyle(
            color: AppTheme.fg,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
    ];

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 28,
        sections: sections,
        pieTouchData: PieTouchData(),
      ),
    );
  }
}
