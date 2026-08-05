import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/agent.dart';
import '../models/app_config.dart';
import '../models/collector_config.dart';
import '../models/dashboard.dart';
import '../models/task.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  ApiService(this._config);

  final AppConfig _config;

  AppConfig get config => _config;

  Map<String, String> get _authHeaders => {
    if (_config.adminToken.isNotEmpty)
      'Authorization': 'Bearer ${_config.adminToken}',
    'Accept': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${_config.baseUrl}$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await http
        .get(_uri(path, query), headers: _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) {
      final msg = response.statusCode == 401
          ? 'Unauthorized — paste admin token in Settings (manager/data/admin-token)'
          : response.body;
      throw ApiException(msg, statusCode: response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getJsonList(String path) async {
    final response = await http
        .get(_uri(path), headers: _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) {
      final msg = response.statusCode == 401
          ? 'Unauthorized — paste admin token in Settings (manager/data/admin-token)'
          : response.body;
      throw ApiException(msg, statusCode: response.statusCode);
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<HealthStatus> health() async {
    final response = await http
        .get(_uri('/api/v1/health'), headers: _authHeaders)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode >= 400) {
      final msg = response.statusCode == 401
          ? 'Unauthorized — paste admin token in Settings (manager/data/admin-token)'
          : response.body;
      throw ApiException(msg, statusCode: response.statusCode);
    }
    return HealthStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AgenticDashboard> dashboard([DashboardFilters? filters]) async {
    final json = await _getJson(
      '/api/v1/dashboard',
      query: filters?.toQueryParams(),
    );
    return AgenticDashboard.fromJson(json);
  }

  Future<TaskListResponse> tasks({
    DashboardFilters? filters,
    int page = 0,
    int size = 80,
  }) async {
    final query = {
      ...?filters?.toQueryParams(),
      'page': page.toString(),
      'size': size.toString(),
    };
    final json = await _getJson('/api/v1/tasks', query: query);
    return TaskListResponse.fromJson(json);
  }

  Future<TaskDetail> task(String id) async {
    final encodedId = Uri.encodeComponent(id);
    final json = await _getJson('/api/v1/tasks/$encodedId');
    return TaskDetail.fromJson(json);
  }

  Future<List<Agent>> agents() async {
    final list = await _getJsonList('/api/v1/agents');
    return list.map((e) => Agent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CollectorStatus> collectors() async {
    final json = await _getJson('/api/v1/collectors');
    return CollectorStatus.fromJson(json);
  }

  Future<McpConfig> mcpConfig() async {
    final json = await _getJson('/api/v1/mcp/config');
    return McpConfig.fromJson(json);
  }

  /// Fetches per-tool collector configurations (filePattern, format).
  Future<Map<String, CollectorConfig>> collectorConfigs() async {
    final json = await _getJson('/api/v1/collectors/config');
    final map = <String, CollectorConfig>{};
    for (final entry in json.entries) {
      if (entry.value is Map<String, dynamic>) {
        map[entry.key] = CollectorConfig.fromJson(
          entry.value as Map<String, dynamic>,
        );
      } else {
        map[entry.key] = const CollectorConfig();
      }
    }
    return map;
  }

  /// Saves per-tool collector configurations to the backend.
  Future<void> saveCollectorConfigs(
    Map<String, CollectorConfig> configs,
  ) async {
    final body = {
      for (final entry in configs.entries) entry.key: entry.value.toJson(),
    };
    final response = await http
        .put(
          _uri('/api/v1/collectors/config'),
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode >= 400) {
      throw ApiException(response.body, statusCode: response.statusCode);
    }
  }
}
