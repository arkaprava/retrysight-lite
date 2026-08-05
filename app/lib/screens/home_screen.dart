import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_info.dart';
import '../models/task.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/cursor_shell.dart';
import 'dashboard_screen.dart';
import 'mcp_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;
  String? _selectedTaskId;

  static const _navItems = [
    CursorNavItem(
      label: 'Dashboard',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
    ),
    CursorNavItem(
      label: 'Tasks',
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
    ),
    CursorNavItem(
      label: 'MCP',
      icon: Icons.extension_outlined,
      selectedIcon: Icons.extension,
    ),
    CursorNavItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
  ];

  void _openTask(String id) {
    setState(() {
      _selectedTaskId = id;
      _index = 1;
    });
  }

  void _clearTask() {
    setState(() => _selectedTaskId = null);
  }

  void _refreshAll() {
    final filters = ref.read(dashboardFiltersProvider);
    ref.invalidate(dashboardProvider(filters));
    ref.invalidate(tasksProvider(filters));
    ref.invalidate(mcpConfigProvider);
    ref.invalidate(healthProvider);
    ref.invalidate(collectorStatusProvider);
    ref.invalidate(agentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final backend = ref.watch(backendServiceProvider);
    final healthAsync = ref.watch(healthProvider);
    final backendHealthy = healthAsync.valueOrNull?.isOk ?? backend.isRunning;
    final brightness = Theme.of(context).brightness;

    return config.when(
      loading: () => Scaffold(
        backgroundColor: AppTheme.bgApp,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppTheme.bgApp,
        body: LoadingError(error: e),
      ),
      data: (cfg) {
        final nav = _navItems[_index];
        final taskBreadcrumb = _index == 1 && _selectedTaskId != null
            ? ref.watch(taskDetailProvider(_selectedTaskId!)).maybeWhen(
                data: (task) => task.displayLabel,
                orElse: () => TaskSummary.formatTaskId(_selectedTaskId!),
              )
            : null;

        Widget body;
        switch (_index) {
          case 0:
            body = DashboardScreen(onOpenTask: _openTask);
          case 1:
            body = TasksScreen(
              selectedTaskId: _selectedTaskId,
              onClearTask: _clearTask,
              onSelectTask: (id) => setState(() => _selectedTaskId = id),
            );
          case 2:
            body = const McpScreen();
          case 3:
            body = const SettingsScreen();
          default:
            body = const SizedBox.shrink();
        }

        return AppTheme.meshBackground(
          brightness: brightness,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                CursorActivityBar(
                  selectedIndex: _index,
                  onSelected: (i) => setState(() {
                    _index = i;
                    if (i != 1) _selectedTaskId = null;
                  }),
                  items: _navItems,
                  onRefresh: _refreshAll,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CursorTitleBar(
                        title: nav.label,
                        breadcrumb: taskBreadcrumb,
                        trailing: StatusChip(
                          label: 'backend',
                          color: backendHealthy
                              ? AppTheme.success
                              : AppTheme.warn,
                          pulse: backendHealthy,
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: KeyedSubtree(
                            key: ValueKey('page_$_index'),
                            child: body,
                          ),
                        ),
                      ),
                      CursorStatusBar(
                        leftItems: [
                          CursorStatusItem(
                            label: cfg.baseUrl,
                            icon: Icons.link,
                          ),
                        ],
                        rightItems: [const CursorStatusItem(label: kAppName)],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
