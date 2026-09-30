import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around `flutter_local_notifications` for OS-level desktop
/// alerts (stale agent, budget exceeded, retry-rate spike). Deliberately
/// scoped to local/OS notifications only — no Slack/webhook/email — so the
/// backend stays local-first with no outbound network dependency for this.
///
/// Every call is best-effort: a notification failing to initialize or show
/// (e.g. the user denied permission, or the platform doesn't support it)
/// must never affect the rest of the app, so all plugin calls are swallowed.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    const darwin = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const settings = InitializationSettings(
      macOS: darwin,
      iOS: darwin,
      linux: linux,
    );
    try {
      await _plugin.initialize(settings);
    } catch (_) {
      // Best effort — e.g. unsupported platform (Windows) or denied init.
    } finally {
      // Mark initialized either way so we don't retry `initialize()` (which
      // can re-prompt for permission) on every subsequent notification.
      _initialized = true;
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          macOS: DarwinNotificationDetails(),
          iOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (_) {
      // Non-critical — never let a notification failure surface to the user
      // as an app error.
    }
  }
}
