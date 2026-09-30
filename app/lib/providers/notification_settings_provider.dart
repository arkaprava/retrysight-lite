import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'retrysight_lite_notification_settings';

class NotificationSettings {
  const NotificationSettings({
    this.staleAgentEnabled = true,
    this.budgetEnabled = true,
    this.retrySpikeEnabled = false,
    this.retrySpikeThresholdPct = 50,
  });

  /// Alert when a previously-active agent stops reporting heartbeats.
  final bool staleAgentEnabled;

  /// Alert once estimated spend reaches the configured cost budget.
  final bool budgetEnabled;

  /// Alert when the last-24h retry rate crosses [retrySpikeThresholdPct].
  final bool retrySpikeEnabled;
  final double retrySpikeThresholdPct;

  NotificationSettings copyWith({
    bool? staleAgentEnabled,
    bool? budgetEnabled,
    bool? retrySpikeEnabled,
    double? retrySpikeThresholdPct,
  }) {
    return NotificationSettings(
      staleAgentEnabled: staleAgentEnabled ?? this.staleAgentEnabled,
      budgetEnabled: budgetEnabled ?? this.budgetEnabled,
      retrySpikeEnabled: retrySpikeEnabled ?? this.retrySpikeEnabled,
      retrySpikeThresholdPct:
          retrySpikeThresholdPct ?? this.retrySpikeThresholdPct,
    );
  }

  Map<String, dynamic> toJson() => {
    'staleAgentEnabled': staleAgentEnabled,
    'budgetEnabled': budgetEnabled,
    'retrySpikeEnabled': retrySpikeEnabled,
    'retrySpikeThresholdPct': retrySpikeThresholdPct,
  };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      staleAgentEnabled: json['staleAgentEnabled'] as bool? ?? true,
      budgetEnabled: json['budgetEnabled'] as bool? ?? true,
      retrySpikeEnabled: json['retrySpikeEnabled'] as bool? ?? false,
      retrySpikeThresholdPct:
          (json['retrySpikeThresholdPct'] as num?)?.toDouble() ?? 50,
    );
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        state = NotificationSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Keep defaults if prefs are unavailable or malformed.
    }
  }

  Future<void> update(NotificationSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
    } catch (_) {
      // Best effort — setting still applies for this session.
    }
  }
}
