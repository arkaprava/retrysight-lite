import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/app_config.dart';
import '../models/collector_config.dart';
import '../providers/app_providers.dart';
import '../services/platform_file_ops.dart';
import '../theme/app_theme.dart';
import '../widgets/cursor_shell.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _managerCtrl;
  late final TextEditingController _dataDirCtrl;
  late final TextEditingController _tokenCtrl;
  final ScrollController _scrollCtrl = ScrollController();
  bool _autoStart = true;
  bool _useTls = false;
  bool _obscureToken = true;
  bool _resetting = false;
  bool _loaded = false;

  final Map<String, TextEditingController> _pathCtrls = {};
  final Map<String, TextEditingController> _patternCtrls = {};
  final Map<String, String> _formatValues = {};
  Map<String, CollectorConfig> _collectorConfigs = {};
  bool _configsLoaded = false;
  bool _loadingConfigs = false;

  static const _collectorFields = [
    ('cursor', 'Cursor'),
    ('claude', 'Claude Code'),
    ('warp', 'Warp/Oz'),
    ('windsurf', 'Windsurf'),
    ('cline', 'Cline'),
    ('aider', 'Aider'),
    ('continue', 'Continue'),
    ('copilot', 'GitHub Copilot'),
  ];

  static const _toolNameMap = {
    'cursor': 'CURSOR',
    'claude': 'CLAUDE_CODE',
    'warp': 'WARP',
    'windsurf': 'WINDSURF',
    'cline': 'CLINE',
    'aider': 'AIDER',
    'continue': 'CONTINUE',
    'copilot': 'GITHUB_COPILOT',
  };

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController();
    _portCtrl = TextEditingController();
    _managerCtrl = TextEditingController();
    _dataDirCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    for (final entry in _collectorFields) {
      _pathCtrls[entry.$1] = TextEditingController();
      _patternCtrls[entry.$1] = TextEditingController();
      _formatValues[entry.$1] = 'jsonl';
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _managerCtrl.dispose();
    _dataDirCtrl.dispose();
    _tokenCtrl.dispose();
    _scrollCtrl.dispose();
    for (final c in _pathCtrls.values) {
      c.dispose();
    }
    for (final c in _patternCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadFromConfig(AppConfig config) {
    _hostCtrl.text = config.host;
    _portCtrl.text = config.port.toString();
    _managerCtrl.text = config.managerPath;
    _dataDirCtrl.text = config.dataDir;
    _tokenCtrl.text = config.adminToken;
    _autoStart = config.autoStartBackend;
    _useTls = config.useTls;

    for (final entry in _collectorFields) {
      _pathCtrls[entry.$1]?.text = _pathValue(config, entry.$1);
    }
    _loaded = true;
    _fetchCollectorConfigs();
  }

  String _pathValue(AppConfig config, String key) {
    switch (key) {
      case 'cursor':
        return config.cursorWatchPaths;
      case 'claude':
        return config.claudeWatchPaths;
      case 'warp':
        return config.warpWatchPaths;
      case 'windsurf':
        return config.windsurfWatchPaths;
      case 'cline':
        return config.clineWatchPaths;
      case 'aider':
        return config.aiderWatchPaths;
      case 'continue':
        return config.continueWatchPaths;
      case 'copilot':
        return config.copilotWatchPaths;
      default:
        return '';
    }
  }

  Future<void> _fetchCollectorConfigs() async {
    if (_configsLoaded || _loadingConfigs) return;
    _loadingConfigs = true;
    try {
      final api = ref.read(apiServiceProvider);
      final configs = await api.collectorConfigs();
      _collectorConfigs = configs;
      for (final entry in _collectorFields) {
        final toolName = _toolNameMap[entry.$1]!;
        final cfg = configs[toolName] ?? const CollectorConfig();
        _formatValues[entry.$1] = cfg.format;
        _patternCtrls[entry.$1]?.text = cfg.filePattern;
      }
      _configsLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {
      _configsLoaded = true;
    } finally {
      _loadingConfigs = false;
    }
  }

  Future<void> _save() async {
    final current = ref.read(appConfigProvider).value ?? const AppConfig();
    final port = int.tryParse(_portCtrl.text.trim()) ?? current.port;
    String val(String key) => _pathCtrls[key]?.text.trim() ?? '';

    final tokenInput = _tokenCtrl.text.trim();
    final config = current.copyWith(
      host: _hostCtrl.text.trim().isEmpty
          ? current.host
          : _hostCtrl.text.trim(),
      port: port,
      adminToken: tokenInput.isNotEmpty ? tokenInput : current.adminToken,
      useTls: _useTls,
      managerPath: _managerCtrl.text.trim(),
      dataDir: _dataDirCtrl.text.trim(),
      autoStartBackend: _autoStart,
      cursorWatchPaths: val('cursor'),
      claudeWatchPaths: val('claude'),
      warpWatchPaths: val('warp'),
      windsurfWatchPaths: val('windsurf'),
      clineWatchPaths: val('cline'),
      aiderWatchPaths: val('aider'),
      continueWatchPaths: val('continue'),
      copilotWatchPaths: val('copilot'),
    );

    await ref.read(appConfigProvider.notifier).update(config);
    ref.invalidate(backendReadyProvider);

    try {
      final api = ref.read(apiServiceProvider);
      final backendConfigs = <String, CollectorConfig>{};
      for (final entry in _collectorFields) {
        final toolName = _toolNameMap[entry.$1]!;
        final format = _formatValues[entry.$1] ?? 'jsonl';
        final pattern = _patternCtrls[entry.$1]?.text.trim() ?? '*.jsonl';
        backendConfigs[toolName] =
            (_collectorConfigs[toolName] ?? const CollectorConfig()).copyWith(
              format: format,
              filePattern: pattern,
            );
      }
      await api.saveCollectorConfigs(backendConfigs);
    } catch (_) {
      // Backend may not be running; path configs saved locally
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: AppTheme.base2,
        ),
      );
    }
  }

  Future<void> _clearToken() async {
    await ref.read(appConfigProvider.notifier).clearAdminToken();
    _tokenCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin token cleared'),
          backgroundColor: AppTheme.base2,
        ),
      );
    }
  }

  Future<void> _resetDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.base2,
        title: const Text(
          'Reset Database',
          style: TextStyle(color: AppTheme.fg),
        ),
        content: const Text(
          'This will delete all data and restart the backend. Continue?',
          style: TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Reset',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _resetting = true);
    try {
      final backend = ref.read(backendServiceProvider);
      final config = ref.read(appConfigProvider).value ?? const AppConfig();

      await backend.stop();

      final rawDir = config.dataDir.isNotEmpty
          ? config.dataDir
          : p.join(config.managerPath, 'data');
      await deleteSqliteDatabaseFiles(rawDir);

      ref.invalidate(backendReadyProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database reset successfully'),
            backgroundColor: AppTheme.base2,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset database: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _restartBackend() async {
    final backend = ref.read(backendServiceProvider);
    await backend.stop();
    ref.invalidate(backendReadyProvider);
    await backend.ensureRunning();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend restarted'),
          backgroundColor: AppTheme.base2,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(appConfigProvider);
    final backend = ref.watch(backendServiceProvider);
    final collectorsAsync = ref.watch(collectorStatusProvider);
    final agentsAsync = ref.watch(agentsProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('$e', style: const TextStyle(color: AppTheme.muted)),
      ),
      data: (config) {
        if (!_loaded) _loadFromConfig(config);

        return Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CursorPanel(
                    title: 'Preferences',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CursorSectionHeader(title: 'API'),
                        TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Host',
                            helperText: 'Manager API host',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            helperText: 'Manager API port',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Use TLS (HTTPS)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.fg,
                                ),
                              ),
                            ),
                            Switch(
                              value: _useTls,
                              onChanged: (v) => setState(() => _useTls = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _tokenCtrl,
                          obscureText: _obscureToken,
                          decoration: InputDecoration(
                            labelText: 'Admin token',
                            helperText:
                                'Bearer token for /api/v1 (also in manager/data/admin-token)',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureToken
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 18,
                              ),
                              onPressed: () => setState(
                                () => _obscureToken = !_obscureToken,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _clearToken,
                              child: const Text('Clear token'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const CursorSectionHeader(title: 'Backend'),
                        TextField(
                          controller: _managerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Manager path',
                            helperText:
                                'Dev only — release builds use bundled backend',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _dataDirCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Data directory',
                            helperText:
                                'SQLite DB and secrets (default: app data dir)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    'Auto-start backend',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.fg,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Launch bundled or dev backend on app start',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _autoStart,
                              onChanged: (v) => setState(() => _autoStart = v),
                            ),
                          ],
                        ),
                        Text(
                          'Backend state: ${backend.state.name}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        collectorsAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (status) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Collectors: ${status.running ? "running" : "stopped"}'
                              '${status.collectors.isNotEmpty ? " (${status.collectors.join(", ")})" : ""}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        agentsAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (agents) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Registered agents: ${agents.length}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const CursorSectionHeader(title: 'Collectors'),
                        const SizedBox(height: 4),
                        for (final entry in _collectorFields) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppTheme.base3.withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.$2,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value:
                                                _formatValues[entry.$1] ??
                                                'jsonl',
                                            isDense: true,
                                            isExpanded: true,
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'jsonl',
                                                child: Text(
                                                  'jsonl',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              DropdownMenuItem(
                                                value: 'plaintext',
                                                child: Text(
                                                  'log',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            onChanged: (v) {
                                              if (v != null) {
                                                setState(
                                                  () =>
                                                      _formatValues[entry.$1] =
                                                          v,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _patternCtrls[entry.$1],
                                  decoration: const InputDecoration(
                                    labelText: 'File pattern',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _pathCtrls[entry.$1],
                                  decoration: const InputDecoration(
                                    labelText: 'Paths (semicolon-separated)',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _save,
                              child: const Text('Save'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _restartBackend,
                              child: const Text('Restart backend'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 12),
                    CursorPanel(
                      title: 'Danger Zone',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Reset SQLite Database',
                            style: TextStyle(color: AppTheme.fg, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Delete all data and restart the backend from scratch.',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _resetting ? null : _resetDatabase,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.danger.withValues(
                                alpha: 0.2,
                              ),
                              foregroundColor: AppTheme.danger,
                            ),
                            child: _resetting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Reset Database'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
