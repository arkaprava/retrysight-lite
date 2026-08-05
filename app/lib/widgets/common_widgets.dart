import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Animated KPI card — counts up from 0 to [value] on first load
/// and whenever the value changes.
class AnimatedKpiCard extends StatefulWidget {
  const AnimatedKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.formatFn,
    this.suffix = '',
    this.decimals = 0,
    this.animate = true,
  });

  final String label;
  final num value;
  final String Function(num)? formatFn;
  final String suffix;
  final int decimals;
  final bool animate;

  @override
  State<AnimatedKpiCard> createState() => _AnimatedKpiCardState();
}

class _AnimatedKpiCardState extends State<AnimatedKpiCard> {
  double _display = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) _display = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant AnimatedKpiCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _display = old.value.toDouble();
    }
  }

  String _format(num raw) {
    if (widget.formatFn != null) return widget.formatFn!(raw);
    if (widget.decimals > 0) {
      return '${raw.toStringAsFixed(widget.decimals)}${widget.suffix}';
    }
    if (raw >= 1000000) {
      return '${(raw / 1000000).toStringAsFixed(1)}M${widget.suffix}';
    }
    if (raw >= 1000) {
      return '${(raw / 1000).toStringAsFixed(1)}k${widget.suffix}';
    }
    return '${raw.toInt()}${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppTheme.glassPanel(
      brightness: brightness,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.muted,
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: _display, end: widget.value.toDouble()),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            onEnd: () => setState(() => _display = widget.value.toDouble()),
            builder: (context, v, _) {
              return Text(
                _format(v),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Static KPI card — use for compound values (e.g. "1.2k / 0.8k").
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppTheme.glassPanel(
      brightness: brightness,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.muted,
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accentSubtle,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.navActiveBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pulse
              ? AppTheme.animatedDot(color: color)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.fg,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class BarChartRow extends StatelessWidget {
  const BarChartRow({
    super.key,
    required this.label,
    required this.value,
    required this.maxValue,
  });

  final String label;
  final int value;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue > 0 ? value / maxValue : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.fg),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: AppTheme.base2,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text('—', style: TextStyle(color: AppTheme.muted));
    }
    final max = values.reduce((a, b) => a > b ? a : b);
    const chars = '▁▂▃▄▅▆▇█';
    final line = values.map((v) {
      if (max == 0) return chars[0];
      final idx = ((v / max) * (chars.length - 1)).round().clamp(
        0,
        chars.length - 1,
      );
      return chars[idx];
    }).join();
    return Text(
      line,
      style: AppTheme.mono.copyWith(color: AppTheme.accent, fontSize: 14),
    );
  }
}

class LoadingError extends StatelessWidget {
  const LoadingError({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
          const SizedBox(height: 12),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class CursorListTile extends StatefulWidget {
  const CursorListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;

  @override
  State<CursorListTile> createState() => _CursorListTileState();
}

class _CursorListTileState extends State<CursorListTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppTheme.accent.withValues(alpha: 0.12)
        : (_hover
              ? AppTheme.hover.withValues(alpha: 0.08)
              : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 13,
                        ),
                        child: widget.title,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle(
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11,
                          ),
                          child: widget.subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String fmtNum(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String fmtPct(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

String fmtUsd(num value) {
  final v = value.toDouble();
  if (v >= 100) return '\$${v.toStringAsFixed(2)}';
  if (v >= 1) return '\$${v.toStringAsFixed(2)}';
  if (v >= 0.01) return '\$${v.toStringAsFixed(3)}';
  return '\$${v.toStringAsFixed(4)}';
}

String fmtTs(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    return DateFormat(
      'yyyy-MM-dd HH:mm:ss',
    ).format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

/// Formats a delta value for display — e.g. "+12.5%" or "-3.2%" or null if no comparison.
String? fmtDelta(num current, num previous) {
  if (previous <= 0) return null;
  final pct = ((current - previous) / previous) * 100;
  if (pct.abs() < 0.05) return '+0.0%';
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1)}%';
}

/// Live KPI card with LIVE badge, animated value, and delta vs previous period.
class LiveKpiCard extends StatefulWidget {
  const LiveKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.prevValue,
    this.formatFn,
    this.suffix = '',
    this.decimals = 0,
    this.deltaLabel = 'vs prev',
    this.showLiveBadge = true,
    this.isRefreshing = false,
  });

  final String label;
  final num value;
  final num? prevValue;
  final String Function(num)? formatFn;
  final String suffix;
  final int decimals;
  final String deltaLabel;
  final bool showLiveBadge;
  final bool isRefreshing;

  @override
  State<LiveKpiCard> createState() => _LiveKpiCardState();
}

class _LiveKpiCardState extends State<LiveKpiCard> {
  double _display = 0;

  @override
  void initState() {
    super.initState();
    _display = widget.value.toDouble();
  }

  @override
  void didUpdateWidget(covariant LiveKpiCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _display = old.value.toDouble();
    }
  }

  String _format(num raw) {
    if (widget.formatFn != null) return widget.formatFn!(raw);
    if (widget.decimals > 0) {
      return '${raw.toStringAsFixed(widget.decimals)}${widget.suffix}';
    }
    if (raw >= 1000000) {
      return '${(raw / 1000000).toStringAsFixed(1)}M${widget.suffix}';
    }
    if (raw >= 1000) {
      return '${(raw / 1000).toStringAsFixed(1)}k${widget.suffix}';
    }
    return '${raw.toInt()}${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    final delta = widget.prevValue != null
        ? fmtDelta(widget.value, widget.prevValue!)
        : null;
    final deltaUp = delta != null && !delta.startsWith('-');
    final deltaColor = delta == null
        ? AppTheme.muted
        : (deltaUp ? AppTheme.success : AppTheme.danger);
    final deltaArrow = delta == null ? '' : (deltaUp ? '▲' : '▼');

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.accent.withValues(alpha: 0.55),
            width: 2,
          ),
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: AppTheme.glassPanel(
        brightness: Theme.of(context).brightness,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.muted,
                      fontSize: 10,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.showLiveBadge) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSubtle,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.navActiveBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppTheme.animatedDot(
                          color: widget.isRefreshing
                              ? AppTheme.success
                              : AppTheme.accent,
                          size: 5,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: _display, end: widget.value.toDouble()),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              onEnd: () => setState(() => _display = widget.value.toDouble()),
              builder: (context, v, _) {
                return Text(
                  _format(v),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
            if (delta != null) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    deltaArrow,
                    style: TextStyle(color: deltaColor, fontSize: 9),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    delta,
                    style: TextStyle(
                      color: deltaColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.deltaLabel,
                    style: TextStyle(color: AppTheme.muted, fontSize: 8),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
