import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Maps tool names to their brand icon assets and brand colors.
class ToolBrand {
  const ToolBrand._(this.name, this.iconAsset, this.brandColor);

  final String name;
  final String iconAsset;
  final Color brandColor;

  static const _map = <String, ToolBrand>{
    'CURSOR': ToolBrand._(
      'Cursor',
      'assets/icons/cursor.png',
      Color(0xFF6C71C4),
    ),
    'CLAUDE_CODE': ToolBrand._(
      'Claude Code',
      'assets/icons/claude.png',
      Color(0xFFD97757),
    ),
    'WARP': ToolBrand._('Warp', 'assets/icons/warp.png', Color(0xFF38BDF8)),
    'WINDSURF': ToolBrand._(
      'Windsurf',
      'assets/icons/windsurf.png',
      Color(0xFF34D399),
    ),
    'CLINE': ToolBrand._('Cline', 'assets/icons/cline.png', Color(0xFFA78BFA)),
    'AIDER': ToolBrand._('Aider', 'assets/icons/aider.png', Color(0xFF859900)),
    'CONTINUE': ToolBrand._(
      'Continue',
      'assets/icons/continue.png',
      Color(0xFF5BCFF0),
    ),
    'GITHUB_COPILOT': ToolBrand._(
      'GitHub Copilot',
      'assets/icons/copilot.png',
      Color(0xFF94A3B8),
    ),
  };

  static const _fallback = ToolBrand._('Tool', '', AppTheme.muted);

  /// Normalizes backend source_tool values to branded tool keys.
  static String normalizeTool(String tool) {
    final key = tool.toUpperCase();
    // ClaudeCollector registers as CLAUDE; jsonl collector uses CLAUDE_CODE.
    if (key == 'CLAUDE') return 'CLAUDE_CODE';
    return key;
  }

  static ToolBrand forTool(String tool) =>
      _map[normalizeTool(tool)] ?? _fallback;

  static Color colorFor(String tool) => forTool(tool).brandColor;
}

/// Renders a tool's brand icon from bundled assets, with a Material icon fallback.
class ToolIcon extends StatelessWidget {
  const ToolIcon(this.tool, {super.key, this.size = 14});

  final String tool;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = ToolBrand.forTool(tool);
    if (brand.iconAsset.isEmpty) {
      return _materialFallback();
    }

    return Image.asset(
      brand.iconAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _materialFallback(),
    );
  }

  Widget _materialFallback() {
    final brand = ToolBrand.forTool(tool);
    final key = ToolBrand.normalizeTool(tool);
    IconData icon;
    switch (key) {
      case 'CURSOR':
        icon = Icons.auto_fix_high;
      case 'CLAUDE_CODE':
        icon = Icons.psychology;
      case 'WARP':
        icon = Icons.bolt;
      case 'WINDSURF':
        icon = Icons.air;
      case 'CLINE':
        icon = Icons.code;
      case 'AIDER':
        icon = Icons.assistant;
      case 'CONTINUE':
        icon = Icons.play_arrow;
      case 'GITHUB_COPILOT':
        icon = Icons.auto_awesome;
      default:
        icon = Icons.smart_toy;
    }
    return Icon(icon, size: size, color: brand.brandColor);
  }
}

/// Shows a tool badge with icon + name, optionally with a subtitle.
class ToolBadge extends StatelessWidget {
  const ToolBadge(this.tool, {super.key, this.size = 12, this.subtitle});

  final String tool;
  final double size;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final brand = ToolBrand.forTool(tool);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolIcon(tool, size: size),
        const SizedBox(width: 4),
        Text(
          tool,
          style: TextStyle(
            color: brand.brandColor,
            fontSize: size * 0.9,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          Text(
            subtitle!,
            style: TextStyle(color: AppTheme.muted, fontSize: size * 0.9),
          ),
        ],
      ],
    );
  }
}
