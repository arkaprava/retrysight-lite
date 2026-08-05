import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../theme/app_theme.dart';
import 'chart_utils.dart';

class SessionSegment {
  SessionSegment({
    required this.eventType,
    required this.summary,
    required this.start,
    required this.end,
    required this.durationMs,
    required this.isRetrySignal,
    this.payload = const {},
  });

  final String eventType;
  final String summary;
  final DateTime start;
  final DateTime end;
  final int durationMs;
  final bool isRetrySignal;
  final Map<String, dynamic> payload;
}

List<SessionSegment> buildSessionSegments(List<TaskTimelineEvent> timeline) {
  if (timeline.isEmpty) return [];

  final parsed = <({TaskTimelineEvent event, DateTime time})>[];
  for (final e in timeline) {
    final t = parseEventTime(e.occurredAt);
    if (t != null) parsed.add((event: e, time: t));
  }
  if (parsed.isEmpty) return [];

  parsed.sort((a, b) => a.time.compareTo(b.time));

  const minSegmentMs = 500;
  final segments = <SessionSegment>[];

  for (var i = 0; i < parsed.length; i++) {
    final start = parsed[i].time;
    final end = i + 1 < parsed.length
        ? parsed[i + 1].time
        : start.add(const Duration(seconds: 1));
    var durationMs = end.difference(start).inMilliseconds;
    if (durationMs < minSegmentMs) durationMs = minSegmentMs;

    segments.add(
      SessionSegment(
        eventType: parsed[i].event.eventType,
        summary: parsed[i].event.summary,
        start: start,
        end: end,
        durationMs: durationMs,
        isRetrySignal: parsed[i].event.isRetrySignal,
        payload: parsed[i].event.payload,
      ),
    );
  }

  return segments;
}

/// A proper time-aligned waterfall chart showing each event as a horizontal bar
/// positioned along a shared time axis.
class SessionWaterfallChart extends StatelessWidget {
  const SessionWaterfallChart({super.key, required this.timeline});

  final List<TaskTimelineEvent> timeline;

  @override
  Widget build(BuildContext context) {
    final segments = buildSessionSegments(timeline);
    if (segments.isEmpty) {
      return Center(
        child: Text('No timed events', style: TextStyle(color: AppTheme.muted)),
      );
    }

    final sessionStart = segments.first.start;
    final sessionEnd = segments.last.end;
    final totalMs = sessionEnd.difference(sessionStart).inMilliseconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header stats
        Row(
          children: [
            _StatChip(label: 'Duration', value: formatDurationMs(totalMs)),
            const SizedBox(width: 12),
            _StatChip(label: 'Phases', value: '${segments.length}'),
            const SizedBox(width: 12),
            _StatChip(
              label: 'Retries',
              value: '${segments.where((s) => s.isRetrySignal).length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Waterfall chart
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _WaterfallBody(
              segments: segments,
              sessionStart: sessionStart,
              totalMs: totalMs,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: _legendTypes(segments).map((type) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: eventTypeColor(type),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  type,
                  style: TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  List<String> _legendTypes(List<SessionSegment> segments) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in segments) {
      if (seen.add(s.eventType)) out.add(s.eventType);
    }
    return out;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.fg,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The main waterfall chart body with left labels, time axis, and bars.
class _WaterfallBody extends StatefulWidget {
  const _WaterfallBody({
    required this.segments,
    required this.sessionStart,
    required this.totalMs,
  });

  final List<SessionSegment> segments;
  final DateTime sessionStart;
  final int totalMs;

  @override
  State<_WaterfallBody> createState() => _WaterfallBodyState();
}

class _WaterfallBodyState extends State<_WaterfallBody> {
  static const _leftLabelW = 110.0;
  static const _rowH = 24.0;
  static const _axisH = 24.0;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    final n = segments.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final plotW = constraints.maxWidth - _leftLabelW - 8;
        final totalH = n * _rowH + _axisH + 8;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: totalH.clamp(80, 480),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: GestureDetector(
                    onTapDown: (d) => _handleTap(
                      d.localPosition,
                      plotW,
                      context,
                      constraints.maxWidth,
                    ),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, totalH),
                      painter: _WaterfallPainter(
                        segments: segments,
                        sessionStart: widget.sessionStart,
                        totalMs: widget.totalMs,
                        plotW: plotW,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Time axis labels beneath
            Padding(
              padding: EdgeInsets.only(left: _leftLabelW, right: 8),
              child: _TimeAxisLabels(
                sessionStart: widget.sessionStart,
                totalMs: widget.totalMs,
                plotW: plotW,
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleTap(
    Offset localPos,
    double plotW,
    BuildContext context,
    double totalW,
  ) {
    final segments = widget.segments;
    final x = localPos.dx - _leftLabelW;
    if (x < 0 || x > plotW) return;

    final row = (localPos.dy / _rowH).floor();
    if (row < 0 || row >= segments.length) return;

    final seg = segments[row];
    final frac = (x / plotW).clamp(0.0, 1.0);
    final tMs = (frac * widget.totalMs).round();
    final target = widget.sessionStart.add(Duration(milliseconds: tMs));

    if (target.isBefore(seg.start) || target.isAfter(seg.end)) return;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: localPos.dx.clamp(8, MediaQuery.of(context).size.width - 220),
        top: localPos.dy.clamp(40, MediaQuery.of(context).size.height - 160),
        child: Material(
          color: AppTheme.base2,
          elevation: 4,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: eventTypeColor(
                    seg.eventType,
                    isRetry: seg.isRetrySignal,
                  ),
                  width: 3,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seg.eventType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: eventTypeColor(
                      seg.eventType,
                      isRetry: seg.isRetrySignal,
                    ),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtTime(seg.start)} \u2192 ${_fmtTime(seg.end)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.muted,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Duration: ${formatDurationMs(seg.durationMs)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.muted,
                    fontFamily: 'monospace',
                  ),
                ),
                if (seg.summary.isNotEmpty && seg.summary != seg.eventType) ...[
                  const SizedBox(height: 4),
                  Text(
                    seg.summary,
                    style: TextStyle(fontSize: 11, color: AppTheme.fg),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (seg.payload.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _modDetail(seg),
                    style: TextStyle(
                      fontSize: 10,
                      color: seg.isRetrySignal
                          ? AppTheme.danger
                          : AppTheme.hover,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 3), entry.remove);
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  /// Build a concise modification detail from the segment's payload.
  String _modDetail(SessionSegment seg) {
    final p = seg.payload;
    if (seg.eventType == 'EDIT') {
      final note = p['note'] as String?;
      final file = p['file'] as String?;
      if (note != null && note.isNotEmpty) return note;
      if (file != null) return 'Modified $file';
      return 'Code edit';
    }
    if (seg.eventType == 'TEST_FAIL') {
      final test = p['test'] as String?;
      return test != null ? 'Failed: $test' : 'Test failure';
    }
    if (seg.eventType == 'DIFF_REJECTED') {
      return 'Diff rejected';
    }
    if (seg.eventType == 'COMPACTION') {
      return 'Context compacted';
    }
    if (seg.eventType == 'SUBAGENT') {
      final name = p['name'] as String?;
      return name != null ? 'Subagent: $name' : '';
    }
    if (seg.eventType == 'TOOL_USAGE') {
      final cmds = p['runCommands'];
      final files = p['readFiles'];
      if (cmds != null || files != null) {
        return 'Ran $cmds cmds, read $files files';
      }
      return '';
    }
    return seg.payload.isNotEmpty
        ? seg.payload.toString().length > 60
              ? '${seg.payload.toString().substring(0, 60)}…'
              : seg.payload.toString()
        : '';
  }
}

/// Time axis tick labels beneath the chart.
class _TimeAxisLabels extends StatelessWidget {
  const _TimeAxisLabels({
    required this.sessionStart,
    required this.totalMs,
    required this.plotW,
  });

  final DateTime sessionStart;
  final int totalMs;
  final double plotW;

  @override
  Widget build(BuildContext context) {
    final tickCount = _niceTickCount(totalMs);
    final labels = <Widget>[];
    for (var i = 0; i <= tickCount; i++) {
      final frac = i / tickCount;
      final t = sessionStart.add(
        Duration(milliseconds: (frac * totalMs).round()),
      );
      final label =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      labels.add(
        Positioned(
          left: frac * plotW - 28,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: AppTheme.muted,
              fontFamily: 'monospace',
            ),
          ),
        ),
      );
    }
    return SizedBox(height: 16, child: Stack(children: labels));
  }

  int _niceTickCount(int ms) {
    if (ms <= 5000) return 5;
    if (ms <= 30000) return 6;
    if (ms <= 120000) return 4;
    return 5;
  }
}

/// Custom painter for the waterfall chart.
class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.segments,
    required this.sessionStart,
    required this.totalMs,
    required this.plotW,
  });

  final List<SessionSegment> segments;
  final DateTime sessionStart;
  final int totalMs;
  final double plotW;

  static const _leftLabelW = 110.0;
  static const _rowH = 24.0;
  static const _barH = 14.0;
  static const _tickLen = 4.0;
  static const _minBarW = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final originX = _leftLabelW;
    final chartH = segments.length * _rowH;

    // ── Background ──
    final bgPaint = Paint()..color = AppTheme.base3;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, chartH), bgPaint);

    // ── Grid lines (vertical time markers) ──
    final tickCount = _niceTickCount();
    final gridPaint = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.5;
    for (var i = 0; i <= tickCount; i++) {
      final x = originX + plotW * i / tickCount;
      canvas.drawLine(Offset(x, 0), Offset(x, chartH), gridPaint);
    }

    // ── Horizontal lane separators ──
    final lanePaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (var i = 1; i < segments.length; i++) {
      final y = i * _rowH;
      canvas.drawLine(
        Offset(originX, y),
        Offset(originX + plotW, y),
        lanePaint,
      );
    }

    // ── Waterfall bars ──
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final yCenter = i * _rowH + _rowH / 2;

      final barX =
          originX +
          plotW * seg.start.difference(sessionStart).inMilliseconds / totalMs;
      final barW = (plotW * seg.durationMs / totalMs).clamp(_minBarW, plotW);
      final barY = yCenter - _barH / 2;

      final color = eventTypeColor(seg.eventType, isRetry: seg.isRetrySignal);

      // Bar fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barW, _barH),
          const Radius.circular(3),
        ),
        Paint()..color = color.withValues(alpha: 0.75),
      );

      // Retry signal: red diamond marker at bar start + red-tinted bar + red border
      if (seg.isRetrySignal) {
        // Red diamond marker at the start
        final markerSize = 8.0;
        final mx = barX;
        final my = yCenter;
        final diamond = Path()
          ..moveTo(mx, my - markerSize)
          ..lineTo(mx + markerSize * 0.6, my)
          ..lineTo(mx, my + markerSize)
          ..lineTo(mx - markerSize * 0.6, my)
          ..close();
        canvas.drawPath(diamond, Paint()..color = AppTheme.danger);

        // Red border around the bar
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barX, barY, barW, _barH),
            const Radius.circular(3),
          ),
          Paint()
            ..color = AppTheme.danger
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke,
        );

        // Red tint underneath
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              barX + 1,
              barY + 1,
              (barW - 2).clamp(0, barW),
              _barH - 2,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = AppTheme.danger.withValues(alpha: 0.15),
        );
      }

      // Duration label on wide bars
      if (barW > 40) {
        _drawText(
          canvas,
          formatDurationMs(seg.durationMs),
          Offset(barX + 4, barY + 2),
          AppTheme.base3,
          9,
        );
      }
    }

    // ── Event labels on the left ──
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final yCenter = i * _rowH + _rowH / 2;
      final color = eventTypeColor(seg.eventType, isRetry: seg.isRetrySignal);

      String label = seg.eventType;
      if (label.length > 14) label = '${label.substring(0, 13)}\u2026';

      _drawText(canvas, label, Offset(4, yCenter - 5), color, 10);
    }

    // ── Time axis ticks along the bottom ──
    final axisY = chartH;
    final axisLine = Paint()
      ..color = AppTheme.muted.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(originX, axisY),
      Offset(originX + plotW, axisY),
      axisLine,
    );

    for (var i = 0; i <= tickCount; i++) {
      final x = originX + plotW * i / tickCount;
      canvas.drawLine(
        Offset(x, axisY),
        Offset(x, axisY + _tickLen),
        Paint()
          ..color = AppTheme.muted.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double fontSize,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: fontSize,
              fontFamily: 'monospace',
              textAlign: TextAlign.left,
            ),
          )
          ..pushStyle(ui.TextStyle(color: color))
          ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 110));
    canvas.drawParagraph(paragraph, at);
  }

  int _niceTickCount() {
    final ms = totalMs;
    if (ms <= 5000) return 5;
    if (ms <= 30000) return 6;
    if (ms <= 120000) return 4;
    return 5;
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) =>
      old.segments != segments ||
      old.totalMs != totalMs ||
      old.sessionStart != sessionStart;
}
