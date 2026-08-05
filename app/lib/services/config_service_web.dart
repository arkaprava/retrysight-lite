import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

class ConfigService {
  static const _prefsKey = 'retrysight_lite_app_config';
  static const _tokenKey = 'retrysight_lite_admin_token_secure';
  static const _secureStorage = FlutterSecureStorage();

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    var config = raw != null
        ? AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>)
        : const AppConfig();

    try {
      final savedToken = await _secureStorage.read(key: _tokenKey) ?? '';
      if (savedToken.isNotEmpty) {
        config = config.copyWith(adminToken: savedToken);
      }
    } catch (_) {
      // Secure storage unavailable in this browser context.
    }

    return config;
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    if (config.adminToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _tokenKey, value: config.adminToken);
      } catch (_) {
        // Fall back to in-memory token for this session only.
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<void> clearAdminToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
  }

  Future<AppConfig> syncAdminTokenFromBackend(AppConfig config) async => config;
}
