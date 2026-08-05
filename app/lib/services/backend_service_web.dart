import '../models/app_config.dart';
import 'api_service.dart';

enum BackendState { stopped, starting, running, error }

/// Web: backend must be started separately (no Process API in browsers).
class BackendService {
  BackendService(this._getConfig);

  final AppConfig Function() _getConfig;
  BackendState _state = BackendState.stopped;
  String? _lastError;
  final String _logBuffer = '';

  BackendState get state => _state;
  String? get lastError => _lastError;
  String get logBuffer => _logBuffer;

  bool get isRunning => _state == BackendState.running;

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
    } catch (e) {
      _state = BackendState.error;
      _lastError =
          'Backend not reachable at ${config.baseUrl}. Start it with: cd manager && npm run start:api ($e)';
      return false;
    }
    _state = BackendState.stopped;
    _lastError = 'Backend returned unexpected health status.';
    return false;
  }

  Future<bool> start() => ensureRunning();

  Future<void> stop() async {
    _state = BackendState.stopped;
    _lastError =
        'Cannot stop backend from the web UI — stop the Node process in your terminal.';
  }

  void dispose() {}
}
