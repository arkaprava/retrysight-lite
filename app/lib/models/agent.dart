class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.developerEmail,
    required this.hostname,
    this.osUsername,
    this.displayName,
    this.installedCollectors,
    this.lastHeartbeatAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String developerEmail;
  final String hostname;
  final String? osUsername;
  final String? displayName;
  final String? installedCollectors;
  final String? lastHeartbeatAt;
  final String? createdAt;

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'] as String,
      name: json['name'] as String,
      developerEmail:
          json['developer_email'] as String? ??
          json['developerEmail'] as String? ??
          '',
      hostname: json['hostname'] as String? ?? '',
      osUsername:
          json['os_username'] as String? ?? json['osUsername'] as String?,
      displayName:
          json['display_name'] as String? ?? json['displayName'] as String?,
      installedCollectors:
          json['installed_collectors'] as String? ??
          json['installedCollectors'] as String?,
      lastHeartbeatAt:
          json['last_heartbeat_at'] as String? ??
          json['lastHeartbeatAt'] as String?,
      createdAt: json['created_at'] as String? ?? json['createdAt'] as String?,
    );
  }
}

class CollectorStatus {
  const CollectorStatus({
    required this.enabled,
    required this.running,
    this.agentId,
    this.collectors = const [],
    this.lastPollAt,
    this.lastFlushAt,
    this.lastError,
  });

  final bool enabled;
  final bool running;
  final String? agentId;
  final List<String> collectors;
  final String? lastPollAt;
  final String? lastFlushAt;
  final String? lastError;

  factory CollectorStatus.fromJson(Map<String, dynamic> json) {
    return CollectorStatus(
      enabled: json['enabled'] as bool? ?? false,
      running: json['running'] as bool? ?? false,
      agentId: json['agentId'] as String?,
      collectors:
          (json['collectors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      lastPollAt: json['lastPollAt'] as String?,
      lastFlushAt: json['lastFlushAt'] as String?,
      lastError: json['lastError'] as String?,
    );
  }
}
