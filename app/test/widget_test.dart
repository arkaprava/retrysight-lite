import 'package:flutter_test/flutter_test.dart';
import 'package:retrysight_lite/models/app_config.dart';
import 'package:retrysight_lite/models/dashboard.dart';
import 'package:retrysight_lite/models/task.dart';
import 'package:retrysight_lite/utils/path_utils.dart';

void main() {
  test('AppConfig baseUrl defaults to loopback 18081', () {
    const config = AppConfig();
    expect(config.baseUrl, 'http://127.0.0.1:18081');
  });

  test('AppConfig baseUrl reflects configured host and port', () {
    const config = AppConfig(host: 'localhost', port: 9090);
    expect(config.baseUrl, 'http://localhost:9090');
  });

  test('AppConfig baseUrl uses TLS when configured', () {
    const config = AppConfig(useTls: true);
    expect(config.baseUrl, 'https://127.0.0.1:18081');
  });

  test('AppConfig round-trips JSON without admin token', () {
    const original = AppConfig(
      host: '127.0.0.1',
      port: 9090,
      adminToken: 'test-token',
      managerPath: '/tmp/manager',
    );
    final restored = AppConfig.fromJson(original.toJson());
    expect(restored.host, original.host);
    expect(restored.port, original.port);
    expect(restored.managerPath, original.managerPath);
    expect(restored.adminToken, '');
  });

  test('AppConfig parses port from string JSON', () {
    final config = AppConfig.fromJson({'port': '9090'});
    expect(config.port, 9090);
  });

  test('DashboardFilters.forQuery applies 24h range', () {
    const filters = DashboardFilters(range: DashboardRange.h24);
    final query = filters.forQuery();
    expect(query.from, isNotNull);
    expect(query.from!.endsWith('Z'), isTrue);
    expect(filters.hasComparisonPeriod, isTrue);
    expect(filters.comparisonDeltaLabel, 'vs prev 24h');
  });

  test('DashboardFilters all-time disables comparison deltas', () {
    const filters = DashboardFilters(range: DashboardRange.all);
    expect(filters.hasComparisonPeriod, isFalse);
    expect(filters.comparisonDeltaLabel, isEmpty);
  });

  test('resolveSafeDataDir rejects traversal', () {
    expect(
      () => resolveSafeDataDir('/tmp/data/../secret'),
      throwsArgumentError,
    );
  });

  test('TaskSummary displayLabel prefers title over id', () {
    const task = TaskSummary(
      id: 'CURSOR:abc-123',
      sourceTool: 'CURSOR',
      status: 'COMPLETED',
      retryCount: 0,
      title: 'Fix login retry loop',
    );
    expect(task.displayLabel, 'Fix login retry loop');
  });

  test('TaskSummary displayLabel strips tool prefix when title missing', () {
    const task = TaskSummary(
      id: 'CURSOR:abc-123',
      sourceTool: 'CURSOR',
      status: 'ACTIVE',
      retryCount: 1,
    );
    expect(task.displayLabel, 'abc-123');
  });

  test('isPathInsideRoot accepts nested files', () {
    expect(
      isPathInsideRoot('/tmp/data/retrysight-lite.db', '/tmp/data'),
      isTrue,
    );
  });
}
