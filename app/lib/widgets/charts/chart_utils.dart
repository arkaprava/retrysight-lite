import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../cursor_shell.dart';

/// Tooltip styling for fl_chart on the Monitor dark theme.
Color chartTooltipBackground(_) => AppTheme.base02;

TextStyle get chartTooltipTextStyle => GoogleFonts.plusJakartaSans(
  color: AppTheme.textHeading,
  fontSize: 11,
  height: 1.35,
);

BarTouchTooltipData monitorBarTooltip({
  required BarTooltipItem? Function(
    BarChartGroupData,
    int,
    BarChartRodData,
    int,
  )
  getTooltipItem,
}) {
  return BarTouchTooltipData(
    getTooltipColor: chartTooltipBackground,
    tooltipBorder: BorderSide(color: AppTheme.borderHover, width: 1),
    tooltipRoundedRadius: AppTheme.radiusSm,
    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tooltipMargin: 8,
    maxContentWidth: 220,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItem: getTooltipItem,
  );
}

LineTouchTooltipData monitorLineTooltip({
  required List<LineTooltipItem?> Function(List<LineBarSpot>) getTooltipItems,
}) {
  return LineTouchTooltipData(
    getTooltipColor: chartTooltipBackground,
    tooltipBorder: BorderSide(color: AppTheme.borderHover, width: 1),
    tooltipRoundedRadius: AppTheme.radiusSm,
    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    tooltipMargin: 8,
    fitInsideHorizontally: true,
    fitInsideVertically: true,
    getTooltipItems: getTooltipItems,
  );
}

/// Dashboard chart series colors — keep legends and plotted series aligned.
const kRetriesSeriesColor = AppTheme.warn;
const kTasksSeriesColor = AppTheme.accent;
const kTokenInputColor = AppTheme.info;
const kTokenOutputColor = AppTheme.accent;
const kActiveTaskColor = AppTheme.warn;
const kCompletedTaskColor = AppTheme.success;
const kAbandonedTaskColor = AppTheme.danger;
const kDurationBarColor = AppTheme.accentSecondary;

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.height = 220,
  });

  final String title;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CursorPanel(
      title: title,
      child: SizedBox(height: height, child: child),
    );
  }
}

Color eventTypeColor(String type, {bool isRetry = false}) {
  if (isRetry) return AppTheme.warn;
  switch (type) {
    case 'SESSION_START':
    case 'SESSION_END':
      return AppTheme.accent;
    case 'TOKEN_USAGE':
      return AppTheme.accentSecondary;
    case 'SUBAGENT':
      return AppTheme.success;
    case 'COMPACTION':
      return AppTheme.danger;
    case 'TASK_COMPLETE':
      return AppTheme.info;
    case 'EDIT':
    case 'TEST_FAIL':
    case 'DIFF_REJECTED':
      return AppTheme.warn;
    default:
      return AppTheme.muted;
  }
}

/// Check if a model name looks like a locally-hosted model.
/// Local model runners (Ollama, LM Studio, etc.) expose models with
/// names like "llama3.2:latest", "mistral:7b", or provider-prefixed names
/// like "ollama/llama3.2".
bool isLocalModel(String model) {
  final lower = model.toLowerCase();
  return lower.startsWith('ollama/') ||
      lower.startsWith('local/') ||
      lower.startsWith('local-') ||
      lower.startsWith('lm-studio/') ||
      lower.startsWith('llamafile/') ||
      lower == 'local' ||
      lower.contains('localhost') ||
      lower.contains('127.0.0.1') ||
      lower.contains('0.0.0.0');
}

/// Color for a model — green-tinged when local, accent otherwise.
Color modelColor(String model) {
  return isLocalModel(model) ? AppTheme.success : AppTheme.accentSecondary;
}

String shortDayLabel(String day) {
  if (day.length >= 10) return day.substring(5);
  return day;
}

String formatDurationMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${(ms / 60000).toStringAsFixed(1)}m';
}

DateTime? parseEventTime(String iso) {
  if (iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}
