import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ember theme — warm, high-contrast dark base with a signature amber accent.
/// Chosen because this app is fundamentally about *retries*: amber reads as
/// attention/caution, which fits the subject better than a generic
/// cyan-on-navy "AI dashboard" palette.
class AppTheme {
  // ─── Ember dark ───
  static const bgApp = Color(0xFF0C0A10);
  static const bgSecondary = Color(0x0BFFFFFF); // rgba(255,255,255,0.045)
  static const bgTertiary = Color(0x12FFFFFF);
  static const bgInset = Color(0x59000000);
  static const textPrimary = Color(0xFFF3EEE6);
  static const textSecondary = Color(0xFFA79FB0);
  static const textMuted = Color(0xFF6F6779);
  static const textHeading = Color(0xFFFBF7F0);

  static const accent = Color(0xFFE7A23A);
  static const accentSecondary = Color(0xFF33C7B0); // teal
  static const accentMuted = Color(0xFFF2BD6D);
  static const accentSubtle = Color(0x24E7A23A); // 14%
  static const accentGlow = Color(0x59E7A23A);

  static const borderGlass = Color(0x14FFFFFF);
  static const borderHover = Color(0x59E7A23A);
  static const navActiveBorder = Color(0x59E7A23A);

  static const success = Color(0xFF4CC38A);
  static const info = Color(0xFF5EB3E4);
  static const warn = Color(0xFFF2954A);
  static const danger = Color(0xFFEE6B64);

  static const chart1 = Color(0xFFE7A23A); // amber (signature)
  static const chart2 = Color(0xFF33C7B0); // teal
  static const chart3 = Color(0xFFE88CA6); // rose
  static const chart4 = Color(0xFF9C8CF2); // violet
  static const chart5 = Color(0xFFF2954A); // orange
  static const chart6 = Color(0xFF5EB3E4); // blue

  // ─── Ember light ───
  static const lightBgApp = Color(0xFFF6F1E7);
  static const lightBgSecondary = Color(0xB8FFFFFF);
  static const lightBgTertiary = Color(0x14140B08);
  static const lightBgInset = Color(0x0A140B08);
  static const lightTextPrimary = Color(0xFF211A12);
  static const lightTextSecondary = Color(0xFF6B6155);
  static const lightTextMuted = Color(0xFF928778);
  static const lightAccent = Color(0xFFB5761F);
  static const lightAccentSecondary = Color(0xFF0E8C79); // teal
  static const lightBorder = Color(0x1A140B08);

  // ─── Legacy aliases (used across widgets) ───
  static const base3 = bgApp;
  static const base2 = Color(0xFF16131C);
  static const base1 = textMuted;
  static const base0 = textSecondary;
  static const base00 = textPrimary;
  static const base01 = textHeading;
  static const base02 = Color(0xFF1C1824);
  static const base03 = bgApp;
  static const fg = textPrimary;
  static const muted = textMuted;
  static const hover = chart3;
  static const border = borderGlass;
  static const green = success;
  static const cyan = info;
  static const blue = info;
  static const violet = chart4;
  static const orange = warn;
  static const red = danger;
  static const yellow = accentMuted;
  static const magenta = chart3;

  // ─── Layout tokens ───
  static const sidebarWidth = 220.0;
  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
  static const blurSigma = 12.0;

  static TextStyle get sans =>
      GoogleFonts.instrumentSans(color: fg, fontSize: 13);
  static TextStyle get mono =>
      GoogleFonts.jetBrainsMono(color: fg, fontSize: 12);
  static TextStyle get display => GoogleFonts.bricolageGrotesque(
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

  /// A single ambient amber glow (top-right) plus a quieter teal counterpart
  /// (bottom-left) — one deliberate source of warmth per corner rather than
  /// several competing radial blobs, so the depth reads as intentional.
  static Widget meshBackground({
    required Widget child,
    Brightness brightness = Brightness.dark,
  }) {
    final isDark = brightness == Brightness.dark;
    final primaryGlow = isDark ? accent : lightAccent;
    final secondaryGlow = isDark ? accentSecondary : lightAccentSecondary;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: isDark ? bgApp : lightBgApp),
        Positioned(
          top: -220,
          right: -160,
          width: 620,
          height: 620,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryGlow.withValues(alpha: isDark ? 0.18 : 0.14),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -260,
          left: -120,
          width: 520,
          height: 520,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  secondaryGlow.withValues(alpha: isDark ? 0.10 : 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
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
    // A brighter top edge plus the ordinary border on the other three sides
    // fakes a subtle inner highlight (Flutter has no inset box-shadow),
    // paired with a taller, softer outer shadow for real elevation.
    final edge = isDark ? borderGlass : lightBorder;
    final topHighlight = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.9);
    return BoxDecoration(
      color: fill ?? (isDark ? bgSecondary : lightBgSecondary),
      borderRadius: BorderRadius.circular(radius),
      border: Border(
        top: BorderSide(color: topHighlight),
        left: BorderSide(color: edge),
        right: BorderSide(color: edge),
        bottom: BorderSide(color: edge),
      ),
      boxShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 32,
                spreadRadius: -12,
                offset: const Offset(0, 12),
              ),
            ]
          : [
              BoxShadow(
                color: lightTextPrimary.withValues(alpha: 0.10),
                blurRadius: 28,
                spreadRadius: -14,
                offset: const Offset(0, 10),
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
      fontFamily: GoogleFonts.instrumentSans().fontFamily,
      textTheme: baseText.copyWith(
        bodyMedium: GoogleFonts.instrumentSans(
          fontSize: 13,
          height: 1.5,
          color: primaryText,
        ),
        bodySmall: GoogleFonts.instrumentSans(
          fontSize: 12,
          color: secondaryText,
        ),
        titleLarge: GoogleFonts.bricolageGrotesque(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDark ? textHeading : lightTextPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: GoogleFonts.instrumentSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primaryText,
        ),
        labelLarge: GoogleFonts.instrumentSans(
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
        labelStyle: GoogleFonts.instrumentSans(color: mutedText, fontSize: 12),
        hintStyle: GoogleFonts.instrumentSans(color: mutedText, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: isDark ? bgApp : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: GoogleFonts.instrumentSans(
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
              textStyle: GoogleFonts.instrumentSans(
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
