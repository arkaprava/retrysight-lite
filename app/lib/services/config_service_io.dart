import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

class ConfigService {
  static const _prefsKey = 'retrysight_lite_app_config';
  static const _legacyPrefsKey = 'retrysitelite_app_config';
  static const _legacyTokenKey = 'retrysight_lite_admin_token';
  static const _legacyTokenKeyOld = 'retrysitelite_admin_token';
  static const _tokenKey = 'retrysight_lite_admin_token_secure';

  static const _secureStorage = FlutterSecureStorage();

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_prefsKey);
    if (raw == null) {
      raw = prefs.getString(_legacyPrefsKey);
      if (raw != null) {
        await prefs.setString(_prefsKey, raw);
        await prefs.remove(_legacyPrefsKey);
      }
    }
    var config = raw != null
        ? AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>)
        : const AppConfig();

    // Load admin token from the OS keychain (Keychain / DPAPI / libsecret).
    String savedToken = '';
    try {
      savedToken = await _secureStorage.read(key: _tokenKey) ?? '';
    } catch (_) {
      savedToken = '';
    }
    // Migrate any legacy shared_preferences token (plaintext) into secure storage.
    if (savedToken.isEmpty) {
      final legacy =
          prefs.getString(_legacyTokenKey) ??
          prefs.getString(_legacyTokenKeyOld) ??
          '';
      if (legacy.isNotEmpty) {
        try {
          await _secureStorage.write(key: _tokenKey, value: legacy);
          await prefs.remove(_legacyTokenKey);
          await prefs.remove(_legacyTokenKeyOld);
          savedToken = legacy;
        } catch (_) {
          savedToken = legacy;
        }
      }
    }
    if (savedToken.isNotEmpty) {
      config = config.copyWith(adminToken: savedToken);
    }

    config = await _applyDefaults(config);
    return config;
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    // Persist admin token in the OS keychain — never in plaintext prefs.
    // Empty token means "leave existing secure-storage value unchanged".
    if (config.adminToken.isNotEmpty) {
      await _secureStorage.write(key: _tokenKey, value: config.adminToken);
    }
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyTokenKeyOld);
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<void> clearAdminToken() async {
    await _secureStorage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyTokenKey);
    await prefs.remove(_legacyTokenKeyOld);
  }

  Future<AppConfig> _applyDefaults(AppConfig config) async {
    final managerPath = config.managerPath.isNotEmpty
        ? config.managerPath
        : _defaultManagerPath();

    var adminToken = config.adminToken;
    if (adminToken.isEmpty) {
      final dataDirs = <String>{
        if (config.dataDir.isNotEmpty) config.dataDir,
        p.join(managerPath, 'data'),
        _installedDataDir(),
      };
      for (final dataDir in dataDirs) {
        adminToken = await _readTokenFile(p.join(dataDir, 'admin-token'));
        if (adminToken.isNotEmpty) break;
      }
    }

    return config.copyWith(
      managerPath: managerPath,
      adminToken: adminToken,
      dataDir: config.dataDir.isNotEmpty
          ? config.dataDir
          : p.join(managerPath, 'data'),
    );
  }

  String _installedDataDir() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Platform.environment['APPDATA'];
    if (home == null || home.isEmpty) return '';

    if (Platform.isMacOS) {
      return p.join(
        home,
        'Library',
        'Application Support',
        'RetrySightLite',
        'data',
      );
    }
    if (Platform.isLinux) {
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      if (xdgData != null && xdgData.isNotEmpty) {
        return p.join(xdgData, 'RetrySightLite', 'data');
      }
      return p.join(home, '.local', 'share', 'RetrySightLite', 'data');
    }
    if (Platform.isWindows) {
      return p.join(home, 'RetrySightLite', 'data');
    }
    return '';
  }

  String _defaultManagerPath() {
    for (final key in ['RETRYSIGHT_MANAGER', 'RETRYSITELITE_MANAGER']) {
      final env = Platform.environment[key];
      if (env != null && env.isNotEmpty && _hasManagerDist(env)) {
        return p.normalize(env);
      }
    }

    final fromExecutable = _managerPathFromExecutable();
    if (fromExecutable != null) return fromExecutable;

    final cwd = Directory.current.path;
    for (final candidate in [
      p.normalize(p.join(cwd, '..', 'manager')),
      p.join(cwd, 'manager'),
    ]) {
      if (_hasManagerDist(candidate)) return candidate;
    }

    return p.normalize(p.join(cwd, '..', 'manager'));
  }

  bool _hasManagerDist(String path) {
    return File(p.join(path, 'dist', 'index.js')).existsSync();
  }

  String? _managerPathFromExecutable() {
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 12; i++) {
      for (final candidate in [
        p.normalize(p.join(dir.path, '..', 'manager')),
        p.join(dir.path, 'manager'),
      ]) {
        if (_hasManagerDist(candidate)) return candidate;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<String> _readTokenFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return '';
    return (await file.readAsString()).trim();
  }
}
