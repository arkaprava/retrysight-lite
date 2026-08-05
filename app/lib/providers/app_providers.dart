import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_config.dart';
import '../models/dashboard.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/backend_service.dart';
import '../services/config_service.dart';

final configServiceProvider = Provider<ConfigService>((ref) => ConfigService());

final appConfigProvider =
    StateNotifierProvider<AppConfigNotifier, AsyncValue<AppConfig>>((ref) {
      return AppConfigNotifier(ref.watch(configServiceProvider));
    });

class AppConfigNotifier extends StateNotifier<AsyncValue<AppConfig>> {
  AppConfigNotifier(this._configService) : super(const AsyncValue.loading()) {
    _load();
  }

  final ConfigService _configService;

  Future<void> _load() async {
    try {
      final config = await _configService.load();
      state = AsyncValue.data(config);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> update(AppConfig config) async {
    final current = state.value;
    var toSave = config;
    if (config.adminToken.isEmpty &&
        current != null &&
        current.adminToken.isNotEmpty) {
      toSave = config.copyWith(adminToken: current.adminToken);
    }
    await _configService.save(toSave);
    state = AsyncValue.data(toSave);
  }

  Future<void> setAdminToken(String token) async {
    final current = state.value ?? const AppConfig();
    final updated = current.copyWith(adminToken: token.trim());
    await _configService.save(updated);
    state = AsyncValue.data(updated);
  }

  Future<void> clearAdminToken() async {
    await _configService.clearAdminToken();
    final current = state.value ?? const AppConfig();
    state = AsyncValue.data(current.copyWith(adminToken: ''));
  }

  Future<void> reload() => _load();
}

final backendServiceProvider = Provider<BackendService>((ref) {
  ref.watch(appConfigProvider);
  final backend = BackendService(
    () => ref.read(appConfigProvider).value ?? const AppConfig(),
  );
  ref.onDispose(backend.dispose);
  return backend;
});

final apiServiceProvider = Provider<ApiService>((ref) {
  final config = ref.watch(appConfigProvider).value ?? const AppConfig();
  return ApiService(config);
});

final backendReadyProvider = FutureProvider<bool>((ref) async {
  final backend = ref.watch(backendServiceProvider);
  return backend.ensureRunning();
});

final dashboardFiltersProvider = StateProvider<DashboardFilters>(
  (ref) => const DashboardFilters(range: DashboardRange.h24),
);

final dashboardProvider =
    FutureProvider.family<AgenticDashboard, DashboardFilters>((
      ref,
      filters,
    ) async {
      ref.watch(backendReadyProvider);
      final api = ref.watch(apiServiceProvider);
      return api.dashboard(filters.forQuery());
    });

final tasksPageProvider = StateProvider<int>((ref) => 0);

final tasksProvider = FutureProvider.family<TaskListResponse, DashboardFilters>(
  (ref, filters) async {
    ref.watch(backendReadyProvider);
    final page = ref.watch(tasksPageProvider);
    final api = ref.watch(apiServiceProvider);
    return api.tasks(filters: filters.forQuery(), page: page);
  },
);

final taskDetailProvider = FutureProvider.family<TaskDetail, String>((
  ref,
  id,
) async {
  ref.watch(backendReadyProvider);
  final api = ref.watch(apiServiceProvider);
  return api.task(id);
});

final mcpConfigProvider = FutureProvider((ref) async {
  ref.watch(backendReadyProvider);
  final api = ref.watch(apiServiceProvider);
  return api.mcpConfig();
});

final collectorStatusProvider = FutureProvider((ref) async {
  ref.watch(backendReadyProvider);
  final api = ref.watch(apiServiceProvider);
  return api.collectors();
});

final agentsProvider = FutureProvider((ref) async {
  ref.watch(backendReadyProvider);
  final api = ref.watch(apiServiceProvider);
  return api.agents();
});

final healthProvider = FutureProvider((ref) async {
  ref.watch(backendReadyProvider);
  final api = ref.watch(apiServiceProvider);
  try {
    return await api.health();
  } catch (_) {
    return null;
  }
});
