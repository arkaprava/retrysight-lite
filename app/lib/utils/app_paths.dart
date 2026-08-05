import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_config.dart';

/// Install / bundle paths for the headless backend binary.
class AppPaths {
  AppPaths._();

  static String get backendBinaryName =>
      Platform.isWindows ? 'retrysight-lite.exe' : 'retrysight-lite';

  static String? get _homeDir {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Platform.environment['APPDATA'];
    if (home == null || home.isEmpty) return null;
    return home;
  }

  /// Default data directory for bundled or standalone installs.
  static String installedDataDir() {
    final home = _homeDir;
    if (home == null) return '';

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

  static String? get installedPrefixDir {
    final data = installedDataDir();
    if (data.isEmpty) return null;
    return p.dirname(data);
  }

  static String? get installedBinDir {
    final prefix = installedPrefixDir;
    if (prefix == null) return null;
    return p.join(prefix, 'bin');
  }

  /// Linux install script (`install-linux.sh`) uses a lowercase prefix.
  static String? get legacyLinuxInstallBinDir {
    if (!Platform.isLinux) return null;
    final home = _homeDir;
    if (home == null) return null;
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final base = (xdg != null && xdg.isNotEmpty)
        ? xdg
        : p.join(home, '.local', 'share');
    return p.join(base, 'retrysight-lite', 'bin');
  }

  /// Paths relative to the running Flutter executable (release bundle).
  static Iterable<String> bundledBackendBinaryCandidates({
    String? executablePath,
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
  }) sync* {
    final mac = isMacOS ?? Platform.isMacOS;
    final win = isWindows ?? Platform.isWindows;
    final linux = isLinux ?? Platform.isLinux;
    final exeDir = executablePath != null
        ? p.dirname(executablePath.replaceAll('\\', '/'))
        : File(Platform.resolvedExecutable).parent.path;
    final name = win ? 'retrysight-lite.exe' : 'retrysight-lite';
    if (mac) {
      yield p.normalize(p.join(exeDir, '..', 'Resources', name));
    } else if (win) {
      yield p.join(exeDir, name);
      yield p.join(exeDir, 'data', name);
    } else if (linux) {
      yield p.join(exeDir, name);
    }
  }

  static Iterable<String> installedBackendBinaryCandidates() sync* {
    final binDir = installedBinDir;
    if (binDir != null) {
      yield p.join(binDir, backendBinaryName);
    }
    final legacy = legacyLinuxInstallBinDir;
    if (legacy != null) {
      yield p.join(legacy, backendBinaryName);
    }
  }

  /// Bundled binary first, then install-script binary, else null (use Node dev path).
  static String? resolveBackendBinary({String? executablePath}) {
    for (final path in [
      ...bundledBackendBinaryCandidates(executablePath: executablePath),
      ...installedBackendBinaryCandidates(),
    ]) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static bool hasManagerDist(String managerPath) {
    return File(p.join(managerPath, 'dist', 'index.js')).existsSync();
  }

  /// Candidate admin-token file paths (backend data dir is source of truth).
  static Iterable<String> adminTokenFileCandidates({
    required String dataDir,
    String managerPath = '',
    Iterable<String> extraDataDirs = const [],
  }) sync* {
    final seen = <String>{};
    for (final dir in [
      if (dataDir.isNotEmpty) dataDir,
      if (managerPath.isNotEmpty) p.join(managerPath, 'data'),
      installedDataDir(),
      ...extraDataDirs,
    ]) {
      final path = p.join(dir, 'admin-token');
      if (seen.add(path)) yield path;
    }
  }

  static String backendWorkingDir({
    required String dataDir,
    String managerPath = '',
  }) {
    if (dataDir.isNotEmpty) return p.dirname(dataDir);
    final prefix = installedPrefixDir;
    if (prefix != null) return prefix;
    if (managerPath.isNotEmpty) return managerPath;
    return Directory.current.path;
  }

  static Map<String, String> backendEnvironment(AppConfig config) {
    return {
      ...Platform.environment,
      'NODE_OPTIONS': '--experimental-sqlite',
      'RETRYSIGHT_HEADLESS': '1',
      'RETRYSIGHT_HOST': config.host,
      'RETRYSIGHT_PORT': config.port.toString(),
      if (config.dataDir.isNotEmpty) 'RETRYSIGHT_DATA_DIR': config.dataDir,
      if (config.dataDir.isNotEmpty)
        'RETRYSIGHT_DB_PATH': p.join(config.dataDir, 'retrysight-lite.db'),
      if (config.cursorWatchPaths.isNotEmpty)
        'RETRYSIGHT_CURSOR_PATHS': config.cursorWatchPaths,
      if (config.claudeWatchPaths.isNotEmpty)
        'RETRYSIGHT_CLAUDE_PATHS': config.claudeWatchPaths,
      if (config.warpWatchPaths.isNotEmpty)
        'RETRYSIGHT_WARP_PATHS': config.warpWatchPaths,
      if (config.windsurfWatchPaths.isNotEmpty)
        'RETRYSIGHT_WINDSURF_PATHS': config.windsurfWatchPaths,
      if (config.clineWatchPaths.isNotEmpty)
        'RETRYSIGHT_CLINE_PATHS': config.clineWatchPaths,
      if (config.aiderWatchPaths.isNotEmpty)
        'RETRYSIGHT_AIDER_PATHS': config.aiderWatchPaths,
      if (config.continueWatchPaths.isNotEmpty)
        'RETRYSIGHT_CONTINUE_PATHS': config.continueWatchPaths,
      if (config.copilotWatchPaths.isNotEmpty)
        'RETRYSIGHT_COPILOT_PATHS': config.copilotWatchPaths,
    };
  }
}
