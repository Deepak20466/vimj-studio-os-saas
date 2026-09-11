import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'auth_storage.dart';

/// Single app-wide poller for `/notifications`, mirroring SyncService's pattern
/// (one static service started once from main.dart, not per-screen). A single
/// `NotificationBellAction` per visible screen would each run its own timer if
/// this didn't exist — and with `IndexedStack` keeping every tab alive at once
/// (see CoachHome/AdminHome), that means every tab's bell polling
/// simultaneously.
///
/// By design (2026-09-11), this only ever updates the in-app bell/notification
/// center — it deliberately does NOT surface anything outside the app (no OS
/// notification-shade/lock-screen popup). An earlier version pushed new items
/// through NotificationService (flutter_local_notifications), but that was
/// turned off at the client's request: notifications should be fully visible
/// and functional inside the app, and silent outside it. See main.dart, which
/// no longer calls NotificationService.init() either.
class NotificationPollingService {
  static final ValueNotifier<int> unreadCount = ValueNotifier(0);
  static Timer? _timer;
  static const _pollInterval = Duration(seconds: 20);
  static bool _polling = false;

  static void start() {
    _timer ??= Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final session = await AuthStorage.load();
      if (session == null) {
        unreadCount.value = 0;
        return;
      }

      final data = await ApiClient.instance.get('/notifications') as Map<String, dynamic>;
      unreadCount.value = data['unread_count'] as int? ?? 0;
    } on ApiException {
      // best-effort — retried on the next interval
    } finally {
      _polling = false;
    }
  }

  /// Called on logout so the next login's first poll starts from a clean badge
  /// instead of briefly showing the previous user's unread count.
  static Future<void> resetOnLogout() async {
    unreadCount.value = 0;
  }
}
