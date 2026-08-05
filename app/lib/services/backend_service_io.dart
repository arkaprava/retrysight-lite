import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_config.dart';
import '../utils/app_paths.dart';
import 'api_service.dart';

enum BackendState { stopped, starting, running, error }

class BackendService {
  BackendService(this._getConfig);

  final AppConfig Function() _getConfig;
  Process? _process;
  BackendState _state = BackendState.stopped;
  String? _lastError;
  String _logBuffer = '';
  static const _maxLogChars = 8000;

  BackendState get state => _state;
  String? get lastError => _lastError;
  String get logBuffer => _logBuffer;

  bool get isRunning => _state == BackendState.running;

  void _appendLog(String data) {
    _logBuffer += data;
    if (_logBuffer.length > _maxLogChars) {
      _logBuffer = _logBuffer.substring(_logBuffer.length - _maxLogChars);
    }
  }

  Future<bool> ensureRunning() async {
    final config = _getConfig();
    final api = ApiService(config);
    try {
      final health = await api.health();
      if (health.isOk) {
        _state = BackendState.running;
        _lastError = null;
        return true;
      }
    } catch (_) {
      // not running yet
    }

    if (!config.autoStartBackend) {
      _state = BackendState.stopped;
      _lastError =
          'Backend not reachable. Start the manager API or enable auto-start.';
      return false;
    }

    return start();
  }

  Future<bool> start() async {
    if (_process != null) {
      return ensureRunning();
    }

    final config = _getConfig();
    final bundledBinary = AppPaths.resolveBackendBinary();
    final managerDir = config.managerPath;
    final distIndex = p.join(managerDir, 'dist', 'index.js');
    final useNodeDist =
        bundledBinary == null && AppPaths.hasManagerDist(managerDir);

    if (bundledBinary == null && !useNodeDist) {
      final hasManagerDir = managerDir.isNotEmpty && Directory(managerDir).existsSync();
      _state = BackendState.error;
      _lastError = hasManagerDir
          ? 'Backend not found. Build manager (npm run build) or use a release app bundle.'
          : 'Backend not found: no bundled binary and manager path missing ($managerDir)';
      return false;
    }

    _state = BackendState.starting;
    _lastError = null;
    _logBuffer = '';

    final env = AppPaths.backendEnvironment(config);
    final workingDir = AppPaths.backendWorkingDir(
      dataDir: config.dataDir,
      managerPath: managerDir,
    );

    try {
      if (bundledBinary != null) {
        _process = await Process.start(
          bundledBinary,
          const ['--headless'],
          workingDirectory: workingDir,
          environment: env,
        );
      } else if (useNodeDist) {
        _process = await Process.start(
          'node',
          [distIndex],
          workingDirectory: managerDir,
          environment: env,
        );
      } else {
        _process = await Process.start(
          'npm',
          ['run', 'start:api'],
          workingDirectory: managerDir,
          environment: env,
        );
      }

      final proc = _process!;
      proc.stdout.transform(const SystemEncoding().decoder).listen(_appendLog);
      proc.stderr.transform(const SystemEncoding().decoder).listen(_appendLog);

      proc.exitCode.then((code) {
        if (identical(_process, proc)) _process = null;
        if (_state == BackendState.running || _state == BackendState.starting) {
          _state = BackendState.error;
          _lastError = 'Backend exited with code $code';
        }
      });

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          final health = await ApiService(_getConfig()).health();
          if (health.isOk) {
            _state = BackendState.running;
            return true;
          }
        } catch (_) {}
      }

      await _killProcess(proc);
      _state = BackendState.error;
      _lastError = 'Backend did not become healthy in time';
      return false;
    } catch (e) {
      await _killProcess(_process);
      _process = null;
      _state = BackendState.error;
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _killProcess(Process? proc) async {
    if (proc == null) return;
    proc.kill(ProcessSignal.sigterm);
    await proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        proc.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  Future<void> stop() async {
    final proc = _process;
    _process = null;
    if (proc != null) {
      await _killProcess(proc);
    }
    _state = BackendState.stopped;
  }

  void dispose() {
    unawaited(stop());
  }
}
