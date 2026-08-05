class AppConfig {
  const AppConfig({
    this.host = '127.0.0.1',
    this.port = 18081,
    this.adminToken = '',
    this.useTls = false,
    this.managerPath = '',
    this.autoStartBackend = true,
    this.dataDir = '',
    this.cursorWatchPaths = '',
    this.claudeWatchPaths = '',
    this.warpWatchPaths = '',
    this.windsurfWatchPaths = '',
    this.clineWatchPaths = '',
    this.aiderWatchPaths = '',
    this.continueWatchPaths = '',
    this.copilotWatchPaths = '',
  });

  final String host;
  final int port;
  final String adminToken;
  final bool useTls;
  final String managerPath;
  final bool autoStartBackend;
  final String dataDir;
  final String cursorWatchPaths;
  final String claudeWatchPaths;
  final String warpWatchPaths;
  final String windsurfWatchPaths;
  final String clineWatchPaths;
  final String aiderWatchPaths;
  final String continueWatchPaths;
  final String copilotWatchPaths;

  String get baseUrl => '${useTls ? 'https' : 'http'}://$host:$port';

  AppConfig copyWith({
    String? host,
    int? port,
    String? adminToken,
    bool? useTls,
    String? managerPath,
    bool? autoStartBackend,
    String? dataDir,
    String? cursorWatchPaths,
    String? claudeWatchPaths,
    String? warpWatchPaths,
    String? windsurfWatchPaths,
    String? clineWatchPaths,
    String? aiderWatchPaths,
    String? continueWatchPaths,
    String? copilotWatchPaths,
  }) {
    return AppConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      adminToken: adminToken ?? this.adminToken,
      useTls: useTls ?? this.useTls,
      managerPath: managerPath ?? this.managerPath,
      autoStartBackend: autoStartBackend ?? this.autoStartBackend,
      dataDir: dataDir ?? this.dataDir,
      cursorWatchPaths: cursorWatchPaths ?? this.cursorWatchPaths,
      claudeWatchPaths: claudeWatchPaths ?? this.claudeWatchPaths,
      warpWatchPaths: warpWatchPaths ?? this.warpWatchPaths,
      windsurfWatchPaths: windsurfWatchPaths ?? this.windsurfWatchPaths,
      clineWatchPaths: clineWatchPaths ?? this.clineWatchPaths,
      aiderWatchPaths: aiderWatchPaths ?? this.aiderWatchPaths,
      continueWatchPaths: continueWatchPaths ?? this.continueWatchPaths,
      copilotWatchPaths: copilotWatchPaths ?? this.copilotWatchPaths,
    );
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'managerPath': managerPath,
    'autoStartBackend': autoStartBackend,
    'dataDir': dataDir,
    'useTls': useTls,
    'cursorWatchPaths': cursorWatchPaths,
    'claudeWatchPaths': claudeWatchPaths,
    'warpWatchPaths': warpWatchPaths,
    'windsurfWatchPaths': windsurfWatchPaths,
    'clineWatchPaths': clineWatchPaths,
    'aiderWatchPaths': aiderWatchPaths,
    'continueWatchPaths': continueWatchPaths,
    'copilotWatchPaths': copilotWatchPaths,
  };

  static int _readPort(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 18081;
    return 18081;
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      host: json['host'] as String? ?? '127.0.0.1',
      port: _readPort(json['port']),
      adminToken:
          '', // token loaded separately — never persisted in config blob
      useTls: json['useTls'] as bool? ?? false,
      managerPath: json['managerPath'] as String? ?? '',
      autoStartBackend: json['autoStartBackend'] as bool? ?? true,
      dataDir: json['dataDir'] as String? ?? '',
      cursorWatchPaths: json['cursorWatchPaths'] as String? ?? '',
      claudeWatchPaths: json['claudeWatchPaths'] as String? ?? '',
      warpWatchPaths: json['warpWatchPaths'] as String? ?? '',
      windsurfWatchPaths: json['windsurfWatchPaths'] as String? ?? '',
      clineWatchPaths: json['clineWatchPaths'] as String? ?? '',
      aiderWatchPaths: json['aiderWatchPaths'] as String? ?? '',
      continueWatchPaths: json['continueWatchPaths'] as String? ?? '',
      copilotWatchPaths: json['copilotWatchPaths'] as String? ?? '',
    );
  }
}
