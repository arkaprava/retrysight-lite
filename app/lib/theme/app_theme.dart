import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Rocket Monitor theme — aligned with agent-retry-platform manager dashboard.
class AppTheme {
  // ─── Monitor dark (Rocket Monitor) ───
  static const bgApp = Color(0xFF0B0F19);
  static const bgSecondary = Color(0x0AFFFFFF); // rgba(255,255,255,0.04)
  static const bgTertiary = Color(0x0FFFFFFF);
  static const bgInset = Color(0x52000000);
  static const textPrimary = Color(0xFFE8ECF4);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);
  static const textHeading = Color(0xFFF8FAFC);

  static const accent = Color(0xFF5BCFF0);
  static const accentSecondary = Color(0xFFA78BFA);
  static const accentMuted = Color(0xFF8BDBF0);
  static const accentSubtle = Color(0x1F5BCFF0); // 12%
  static const accentGlow = Color(0x595BCFF0);

  static const borderGlass = Color(0x0FFFFFFF);
  static const borderHover = Color(0x475BCFF0);
  static const navActiveBorder = Color(0x595BCFF0);

  static const success = Color(0xFF34D399);
  static const info = Color(0xFF38BDF8);
  static const warn = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static const chart1 = Color(0xFF5BCFF0);
  static const chart2 = Color(0xFFA78BFA);
  static const chart3 = Color(0xFF34D399);
  static const chart4 = Color(0xFFFBBF24);
  static const chart5 = Color(0xFFF472B6);
  static const chart6 = Color(0xFF38BDF8);

  // ─── Monitor light ───
  static const lightBgApp = Color(0xFFEEF2F8);
  static const lightBgSecondary = Color(0xB8FFFFFF);
  static const lightTextPrimary = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightTextMuted = Color(0xFF64748B);
  static const lightAccent = Color(0xFF0E9EB0);
  static const lightAccentSecondary = Color(0xFF7C3AED);
  static const lightBorder = Color(0x140B0F19);

  // ─── Legacy aliases (used across widgets) ───
  static const base3 = bgApp;
  static const base2 = Color(0xFF141A28);
  static const base1 = textMuted;
  static const base0 = textSecondary;
  static const base00 = textPrimary;
  static const base01 = textHeading;
  static const base02 = Color(0xFF1A2235);
  static const base03 = bgApp;
  static const fg = textPrimary;
  static const muted = textMuted;
  static const hover = accentSecondary;
  static const border = borderGlass;
  static const green = success;
  static const cyan = accent;
  static const blue = accent;
  static const violet = accentSecondary;
  static const orange = Color(0xFFFB923C);
  static const red = danger;
  static const yellow = warn;
  static const magenta = chart5;

  // ─── Layout tokens ───
  static const sidebarWidth = 220.0;
  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
  static const blurSigma = 12.0;

  static TextStyle get sans =>
      GoogleFonts.plusJakartaSans(color: fg, fontSize: 13);
  static TextStyle get mono =>
      GoogleFonts.jetBrainsMono(color: fg, fontSize: 12);
  static TextStyle get display => GoogleFonts.plusJakartaSans(
    color: textHeading,
    fontWeight: FontWeight.w700,
  );

  static BoxDecoration get scaffoldDecoration =>
      BoxDecoration(color: bgApp, gradient: meshGradient(Brightness.dark));

  static LinearGradient? meshGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgApp, bgApp],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [lightBgApp, lightBgApp],
    );
  }

  static Widget meshBackground({
    required Widget child,
    Brightness brightness = Brightness.dark,
  }) {
    final isDark = brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: isDark ? bgApp : lightBgApp),
        if (isDark) ...[
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            height: 400,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.2,
                  colors: [accent.withValues(alpha: 0.14), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -80,
            width: 320,
            height: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    accentSecondary.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            width: 280,
            height: 280,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: 0.06), Colors.transparent],
                ),
              ),
            ),
          ),
        ] else ...[
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            height: 300,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.1,
                  colors: [
                    lightAccent.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
        child,
      ],
    );
  }

  static BoxDecoration glassDecoration({
    double radius = radiusMd,
    Color? fill,
    Brightness brightness = Brightness.dark,
  }) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      color: fill ?? (isDark ? bgSecondary : lightBgSecondary),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: isDark ? borderGlass : lightBorder),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
          : [
              BoxShadow(
                color: lightTextPrimary.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  static Widget glassPanel({
    required Widget child,
    double radius = radiusMd,
    Color? fill,
    EdgeInsetsGeometry? padding,
    Brightness brightness = Brightness.dark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: glassDecoration(
            radius: radius,
            fill: fill,
            brightness: brightness,
          ),
          child: child,
        ),
      ),
    );
  }

  static ThemeData dark() => _buildTheme(Brightness.dark);

  static ThemeData light() => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? bgApp : lightBgApp;
    final surface = isDark ? base2 : Colors.white;
    final primaryText = isDark ? textPrimary : lightTextPrimary;
    final secondaryText = isDark ? textSecondary : lightTextSecondary;
    final mutedText = isDark ? textMuted : lightTextMuted;
    final primaryAccent = isDark ? accent : lightAccent;
    final outline = isDark ? borderGlass : lightBorder;

    final baseText = (isDark ? ThemeData.dark() : ThemeData.light()).textTheme
        .apply(bodyColor: primaryText, displayColor: primaryText);

    final scheme = isDark
        ? const ColorScheme.dark(
            surface: base2,
            onSurface: textPrimary,
            primary: accent,
            onPrimary: bgApp,
            secondary: accentSecondary,
            onSecondary: bgApp,
            error: danger,
            outline: borderGlass,
          )
        : ColorScheme.light(
            surface: Colors.white,
            onSurface: lightTextPrimary,
            primary: lightAccent,
            onPrimary: Colors.white,
            secondary: lightAccentSecondary,
            onSecondary: Colors.white,
            error: danger,
            outline: lightBorder,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: baseText.copyWith(
        bodyMedium: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          height: 1.5,
          color: primaryText,
        ),
        bodySmall: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: secondaryText,
        ),
        titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDark ? textHeading : lightTextPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        labelLarge: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
      ),
      dividerColor: outline,
      iconTheme: IconThemeData(color: mutedText, size: 20),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: outline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        iconColor: mutedText,
        textColor: primaryText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? bgInset : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: primaryAccent, width: 1),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(color: mutedText, fontSize: 12),
        hintStyle: GoogleFonts.plusJakartaSans(color: mutedText, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: isDark ? bgApp : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: primaryText,
              side: BorderSide(color: outline),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((s) {
                if (s.contains(WidgetState.hovered)) return accentSubtle;
                return null;
              }),
            ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryAccent : mutedText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primaryAccent.withValues(alpha: 0.35)
              : surface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryAccent),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          primaryAccent.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(radiusSm),
        thickness: WidgetStateProperty.all(8),
      ),
    );
  }

  static Color get background => bgApp;

  static List<BoxShadow> glow({
    Color? color,
    double radius = 12,
    double spread = 0,
  }) {
    final c = color ?? accent;
    return [
      BoxShadow(
        color: c.withValues(alpha: 0.22),
        blurRadius: radius,
        spreadRadius: spread,
      ),
      BoxShadow(
        color: c.withValues(alpha: 0.08),
        blurRadius: radius * 2,
        spreadRadius: spread,
      ),
    ];
  }

  static Widget animatedDot({
    required Color color,
    double size = 6,
    double sizeLarge = 10,
  }) {
    return _PulsingDot(color: color, size: size, sizeLarge: sizeLarge);
  }

  static List<Color> chartSeries(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [chart1, chart2, chart3, chart4, chart5, chart6];
    }
    return const [
      lightAccent,
      lightAccentSecondary,
      success,
      warn,
      chart5,
      info,
    ];
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({
    required this.color,
    required this.size,
    required this.sizeLarge,
  });
  final Color color;
  final double size;
  final double sizeLarge;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(
      begin: 1.0,
      end: 1.6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Transform.scale(
          scale: _anim.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
