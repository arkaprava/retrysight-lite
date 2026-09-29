import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../utils/app_paths.dart';

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
    // Best-effort: on an ad-hoc-signed (no Team ID) build, macOS Keychain
    // writes can fail with errSecMissingEntitlement (-34018) even though the
    // app never requested a shared access group. Swallow that here (as
    // `_persistAdminToken` already does) so a Keychain failure never aborts
    // the rest of this save — in particular, callers like
    // `syncAdminTokenFromBackend` must still see this return normally so the
    // corrected token reaches in-memory app state, even if it can't survive
    // a restart via the keychain on this build.
    if (config.adminToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _tokenKey, value: config.adminToken);
      } catch (_) {
        // Non-fatal — token still applies for this session; see comment above.
      }
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
    final bundledBinary = AppPaths.resolveBackendBinary();
    final managerPath = config.managerPath.isNotEmpty
        ? config.managerPath
        : (bundledBinary != null ? '' : _defaultManagerPath());

    final dataDir = config.dataDir.isNotEmpty
        ? config.dataDir
        : _defaultDataDir(bundledBinary, managerPath);

    var adminToken = config.adminToken;
    // Only fall back to the on-disk token on first run (no token configured yet).
    // Once a token is set, `syncAdminTokenFromBackend` (called after the backend
    // starts) is the sole path that re-syncs it — otherwise a user-provided
    // token (e.g. pointing at a different manager instance) gets silently
    // clobbered by whatever the local data dir happens to contain.
    if (adminToken.isEmpty) {
      final fileToken = await _readAdminTokenFromFiles(
        dataDir: dataDir,
        managerPath: managerPath,
      );
      if (fileToken.isNotEmpty) {
        adminToken = fileToken;
      }
    }

    final resolved = config.copyWith(
      managerPath: managerPath,
      adminToken: adminToken,
      dataDir: dataDir,
    );

    if (adminToken.isNotEmpty && adminToken != config.adminToken) {
      await _persistAdminToken(adminToken);
    }

    return resolved;
  }

  /// Re-read admin-token from backend data dirs after the server starts.
  Future<AppConfig> syncAdminTokenFromBackend(AppConfig config) async {
    final fileToken = await _readAdminTokenFromFiles(
      dataDir: config.dataDir,
      managerPath: config.managerPath,
    );
    if (fileToken.isEmpty || fileToken == config.adminToken) {
      return config;
    }

    final updated = config.copyWith(adminToken: fileToken);
    await _persistAdminToken(fileToken);
    await save(updated);
    return updated;
  }

  Future<void> _persistAdminToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (_) {
      // Best effort — token remains in memory for this session.
    }
  }

  Future<String> _readAdminTokenFromFiles({
    required String dataDir,
    required String managerPath,
  }) async {
    // Only fall back to a dev checkout's `manager/data` when we're actually
    // NOT running a bundled/installed binary. Including it unconditionally
    // meant that on a machine that also has this repo checked out with a
    // stale `manager/data/admin-token` left over from `npm run dev`, the
    // installed app could pick up that unrelated dev token as its initial
    // guess (before the real backend has started and written its own token),
    // which then persists as a wrong, never-corrected token if the later
    // resync also fails to persist (see `save`).
    final extraDataDirs = AppPaths.resolveBackendBinary() == null
        ? [p.join(_defaultManagerPath(), 'data')]
        : const <String>[];
    for (final path in AppPaths.adminTokenFileCandidates(
      dataDir: dataDir,
      managerPath: managerPath,
      extraDataDirs: extraDataDirs,
    )) {
      final token = await _readTokenFile(path);
      if (token.isNotEmpty) return token;
    }
    return '';
  }

  String _defaultDataDir(String? bundledBinary, String managerPath) {
    if (bundledBinary != null) {
      final installed = AppPaths.installedDataDir();
      if (installed.isNotEmpty) return installed;
    }
    if (managerPath.isNotEmpty) {
      return p.join(managerPath, 'data');
    }
    return AppPaths.installedDataDir();
  }

  String _defaultManagerPath() {
    for (final key in ['RETRYSIGHT_MANAGER', 'RETRYSITELITE_MANAGER']) {
      final env = Platform.environment[key];
      if (env != null && env.isNotEmpty && AppPaths.hasManagerDist(env)) {
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
      if (AppPaths.hasManagerDist(candidate)) return candidate;
    }

    return p.normalize(p.join(cwd, '..', 'manager'));
  }

  String? _managerPathFromExecutable() {
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 12; i++) {
      for (final candidate in [
        p.normalize(p.join(dir.path, '..', 'manager')),
        p.join(dir.path, 'manager'),
      ]) {
        if (AppPaths.hasManagerDist(candidate)) return candidate;
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
