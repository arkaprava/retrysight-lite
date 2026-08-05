import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/cursor_shell.dart';

class McpScreen extends ConsumerWidget {
  const McpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mcpAsync = ref.watch(mcpConfigProvider);

    return mcpAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => LoadingError(
        error: e,
        onRetry: () => ref.invalidate(mcpConfigProvider),
      ),
      data: (cfg) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            CursorPanel(
              title: 'MCP server',
              actions: [
                _CopyButton(
                  label: 'Copy',
                  onCopy: () =>
                      _copy(context, '${cfg.command} ${cfg.args.join(' ')}'),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Standard MCP server configuration — add this server to any MCP client.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Transport', value: cfg.transport),
                  _InfoRow(label: 'Endpoint', value: cfg.endpointHint),
                  _InfoRow(label: 'Command', value: cfg.command),
                  _InfoRow(label: 'Args', value: cfg.args.join(' ')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CursorPanel(
              title: 'JSON Config',
              actions: [
                _CopyButton(
                  label: 'Copy',
                  onCopy: () => _copy(context, cfg.configJson),
                ),
              ],
              child: SelectableText(
                cfg.configJson,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.fg,
                  height: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: AppTheme.base2,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.onCopy});

  final String label;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onCopy,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
