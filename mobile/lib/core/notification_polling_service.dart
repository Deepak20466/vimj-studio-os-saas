import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'notification_service.dart';

/// Single app-wide poller for `/notifications`, mirroring SyncService's pattern
/// (one static service started once from main.dart, not per-screen). A single
/// `NotificationBellAction` per visible screen would each run its own timer if
/// this didn't exist — and with `IndexedStack` keeping every tab alive at once
/// (see CoachHome/AdminHome), that means every tab's bell polling
/// simultaneously, and — once this fires a real system notification for a new
/// item — the same message popping multiple times over.
///
/// This is also what makes a notification appear "outside the app" (the phone's
/// notification shade, lock screen) rather than only inside the in-app bell:
/// while the app process is alive (open or recently backgrounded — Android
/// keeps it running for a while, not indefinitely), a new item is pushed as a
/// real OS notification via NotificationService, not just added to a list you
/// have to open the app to see. It stops the moment Android fully kills the
/// process. Delivery that survives the app being closed for hours/days, the
/// way WhatsApp does it, needs push from a server (Firebase Cloud Messaging) —
/// this local-only approach is not that; see mobile/README.md for what's needed
/// to add real push.
class NotificationPollingService {
  static final ValueNotifier<int> unreadCount = ValueNotifier(0);
  static Timer? _timer;
  static const _pollInterval = Duration(seconds: 20);
  static const _lastSeenKey = 'vimj_last_seen_notification_id';
  static int? _lastSeenId;
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
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) return;

      _lastSeenId ??= await _loadLastSeenId();
      final maxId = items.map((n) => n['id'] as int).reduce((a, b) => a > b ? a : b);

      // First poll after a fresh install/login: baseline to what already exists
      // instead of popping a system notification for every pre-existing unread
      // item at once.
      if (_lastSeenId == 0) {
        await _saveLastSeenId(maxId);
        _lastSeenId = maxId;
        return;
      }

      final newOnes = items.where((n) => (n['id'] as int) > _lastSeenId!).toList()
        ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      for (final n in newOnes) {
        await NotificationService.show(
          id: n['id'] as int,
          title: n['title'] as String,
          body: n['message'] as String,
        );
      }
      if (maxId > _lastSeenId!) {
        await _saveLastSeenId(maxId);
        _lastSeenId = maxId;
      }
    } on ApiException {
      // best-effort — retried on the next interval
    } finally {
      _polling = false;
    }
  }

  static Future<int> _loadLastSeenId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSeenKey) ?? 0;
  }

  static Future<void> _saveLastSeenId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSeenKey, id);
  }

  /// Called on logout so the next login's first poll re-baselines instead of
  /// treating a different user's whole notification history as "new".
  static Future<void> resetOnLogout() async {
    _lastSeenId = null;
    unreadCount.value = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSeenKey);
  }
}
