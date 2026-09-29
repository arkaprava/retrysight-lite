import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_info.dart';
import '../theme/app_theme.dart';

class CursorActivityBar extends StatelessWidget {
  const CursorActivityBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
    this.onRefresh,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<CursorNavItem> items;
  final VoidCallback? onRefresh;

  static const width = AppTheme.sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.blurSigma,
          sigmaY: AppTheme.blurSigma,
        ),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.bgSecondary : AppTheme.lightBgSecondary,
            border: Border(
              right: BorderSide(
                color: isDark ? AppTheme.borderGlass : AppTheme.lightBorder,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: Image.asset(
                        kAppLogoAsset,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kAppName,
                            style: GoogleFonts.bricolageGrotesque(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTheme.textHeading
                                  : AppTheme.lightTextPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Performance Monitoring',
                            style: GoogleFonts.instrumentSans(
                              fontSize: 10,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _SidebarNavItem(
                        item: items[i],
                        selected: i == selectedIndex,
                        onTap: () => onSelected(i),
                      ),
                  ],
                ),
              ),
              if (onRefresh != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.lightTextSecondary,
                      side: BorderSide(
                        color: isDark
                            ? AppTheme.borderGlass
                            : AppTheme.lightBorder,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class CursorNavItem {
  const CursorNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CursorNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppTheme.accent : AppTheme.lightAccent;

    Color bg = Colors.transparent;
    Color fg = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    Border? border;

    if (widget.selected) {
      bg = AppTheme.accentSubtle;
      fg = accent;
      border = Border.all(color: AppTheme.navActiveBorder);
    } else if (_hover) {
      bg = isDark ? AppTheme.bgTertiary : Colors.white.withValues(alpha: 0.5);
      fg = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: border,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.selected
                        ? widget.item.selectedIcon
                        : widget.item.icon,
                    size: 18,
                    color: fg,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      style: GoogleFonts.instrumentSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CursorTitleBar extends StatelessWidget {
  const CursorTitleBar({
    super.key,
    required this.title,
    this.breadcrumb,
    this.trailing,
  });

  final String title;
  final String? breadcrumb;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.bgApp.withValues(alpha: 0.6)
            : AppTheme.lightBgApp.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.borderGlass : AppTheme.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? AppTheme.textHeading : AppTheme.lightTextPrimary,
              letterSpacing: -0.2,
            ),
          ),
          if (breadcrumb != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '›',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ),
            Text(
              breadcrumb!,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: AppTheme.accent,
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class CursorStatusBar extends StatelessWidget {
  const CursorStatusBar({
    super.key,
    required this.leftItems,
    required this.rightItems,
  });

  final List<Widget> leftItems;
  final List<Widget> rightItems;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.bgInset : Colors.white.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.borderGlass : AppTheme.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          ...leftItems.expand((w) => [w, const SizedBox(width: 12)]),
          const Spacer(),
          ...rightItems.expand((w) => [w, const SizedBox(width: 12)]),
        ],
      ),
    );
  }
}

class CursorStatusItem extends StatelessWidget {
  const CursorStatusItem({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class CursorPanel extends StatelessWidget {
  const CursorPanel({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions,
    this.legend,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  /// Small colored-dot + label items shown at the right of the header — for
  /// e.g. a multi-series chart's legend, so it reads together with the title
  /// instead of floating separately under the chart.
  final List<Widget>? legend;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    return AppTheme.glassPanel(
      brightness: brightness,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, subtitle == null ? 12 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.bricolageGrotesque(
                          color: isDark
                              ? AppTheme.textHeading
                              : AppTheme.lightTextPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: GoogleFonts.instrumentSans(
                            color: AppTheme.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (legend != null)
                  Wrap(
                    spacing: 14,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: legend!,
                  ),
                ...?actions,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class CursorSectionHeader extends StatelessWidget {
  const CursorSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        '┃ ${title.toUpperCase()}',
        style: GoogleFonts.instrumentSans(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
