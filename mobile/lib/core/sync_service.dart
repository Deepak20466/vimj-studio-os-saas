import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_client.dart';
import 'offline_queue.dart';

/// Watches connectivity and flushes the offline attendance queue whenever
/// the device comes back online.
class SyncService {
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _syncing = false;

  static void start() {
    _subscription ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        syncNow();
      }
    });
  }

  static void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  static Future<SyncResult> syncNow() async {
    if (_syncing) return SyncResult(synced: 0, failed: 0);
    _syncing = true;
    var synced = 0;
    var failed = 0;
    try {
      final items = await OfflineQueue.pending();
      for (final item in items) {
        try {
          await ApiClient.instance.post('/attendance/mark-student', body: item.toApiBody());
          if (item.id != null) await OfflineQueue.remove(item.id!);
          synced++;
        } on ApiException catch (e) {
          // 400s (e.g. duplicate/deadline passed) are not retryable — drop them
          // so they don't jam the queue forever. Network errors leave the item
          // queued for the next sync attempt.
          if (e.statusCode >= 400 && e.statusCode < 500 && item.id != null) {
            await OfflineQueue.remove(item.id!);
          }
          failed++;
        } catch (_) {
          failed++;
        }
      }
    } finally {
      _syncing = false;
    }
    return SyncResult(synced: synced, failed: failed);
  }
}

class SyncResult {
  final int synced;
  final int failed;
  SyncResult({required this.synced, required this.failed});
}
