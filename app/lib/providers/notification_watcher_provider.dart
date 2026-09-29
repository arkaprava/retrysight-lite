import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dashboard.dart';
import '../services/notification_service.dart';
import 'app_providers.dart';
import 'notification_settings_provider.dart';

/// Polls the dashboard independently of whichever tab is visible and fires
/// OS notifications when a threshold is newly crossed. Kept alive for the
/// app's lifetime by being watched from `HomeScreen` (the one widget that's
/// always mounted) rather than from `DashboardScreen`, whose own polling
/// timer stops as soon as the user switches tabs.
final notificationWatcherProvider = Provider<void>((ref) {
  var staleAgentsNotified = <String>{};
  var budgetNotified = false;
  var retrySpikeNotified = false;

  Future<void> check() async {
    final settings = ref.read(notificationSettingsProvider);
    if (!settings.staleAgentEnabled &&
        !settings.budgetEnabled &&
        !settings.retrySpikeEnabled) {
      return;
    }
    try {
      final api = ref.read(apiServiceProvider);
      final dash = await api.dashboard(
        const DashboardFilters(range: DashboardRange.h24).forQuery(),
      );

      if (settings.staleAgentEnabled) {
        final currentlyStale = <String>{};
        for (final agent in dash.agentHealth) {
          if (!agent.stale) continue;
          currentlyStale.add(agent.agentId);
          if (staleAgentsNotified.contains(agent.agentId)) continue;
          staleAgentsNotified.add(agent.agentId);
          await NotificationService.instance.show(
            id: agent.agentId.hashCode,
            title: 'Agent went stale',
            body: '${agent.agentName} has stopped reporting heartbeats.',
          );
        }
        // Allow a future re-notification if an agent goes stale again after recovering.
        staleAgentsNotified = staleAgentsNotified.intersection(currentlyStale);
      }

      if (settings.budgetEnabled && dash.budgetUsedFraction != null) {
        final overBudget = dash.budgetUsedFraction! >= 1.0;
        if (overBudget && !budgetNotified) {
          budgetNotified = true;
          await NotificationService.instance.show(
            id: 'budget'.hashCode,
            title: 'Cost budget exceeded',
            body:
                'Estimated spend is at ${(dash.budgetUsedFraction! * 100).toStringAsFixed(0)}% '
                'of your \$${dash.budgetUsd!.toStringAsFixed(0)} budget.',
          );
        } else if (!overBudget) {
          budgetNotified = false;
        }
      }

      if (settings.retrySpikeEnabled) {
        final thresholdFraction = settings.retrySpikeThresholdPct / 100;
        final spiking = dash.retryRate >= thresholdFraction;
        if (spiking && !retrySpikeNotified) {
          retrySpikeNotified = true;
          await NotificationService.instance.show(
            id: 'retrySpike'.hashCode,
            title: 'Retry rate spike',
            body:
                'Retry rate over the last 24h is '
                '${(dash.retryRate * 100).toStringAsFixed(0)}%, over your '
                '${settings.retrySpikeThresholdPct.toStringAsFixed(0)}% threshold.',
          );
        } else if (!spiking) {
          retrySpikeNotified = false;
        }
      }
    } catch (_) {
      // Non-fatal — the backend may not be reachable this cycle; try again
      // on the next poll.
    }
  }

  final timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  unawaited(check());

  ref.onDispose(timer.cancel);
});
