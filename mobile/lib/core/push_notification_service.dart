import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';
import 'auth_storage.dart';
import 'notification_service.dart';

/// Connects authenticated Android devices to server-triggered FCM alerts.
/// Firebase setup is optional during local development until the Android app
/// is registered in the VIMJ Firebase project.
class PushNotificationService {
  static bool _ready = false;
  static bool _initialized = false;
  static bool _permissionRequested = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isAndroid) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _ready = true;
      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'VIMJ Studio Update';
        final body = message.notification?.body ?? '';
        if (body.isNotEmpty) {
          NotificationService.show(
            id: message.hashCode,
            title: title,
            body: body,
          );
        }
      });
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => _register(token),
      );
      await syncToken();
    } catch (_) {
      // Firebase setup is project-specific; never prevent login or local app
      // notifications when it is temporarily unavailable.
      _ready = false;
    }
  }

  static Future<void> syncToken() async {
    if (!_ready || !Platform.isAndroid) return;
    try {
      if (await AuthStorage.load() == null) return;
      if (!_permissionRequested) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        _permissionRequested = true;
      }
      await NotificationService.init();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (_) {
      // Best effort; token refresh will retry when connectivity returns.
    }
  }

  static Future<void> _register(String token) async {
    if (!_ready || await AuthStorage.load() == null) return;
    try {
      await ApiClient.instance.post('/notifications/device-token', body: {
        'token': token,
        'platform': 'android',
      });
    } catch (_) {
      // Retried the next time the app opens or FCM rotates its token.
    }
  }

  static Future<void> unregisterCurrentDevice() async {
    if (!_ready || !Platform.isAndroid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && await AuthStorage.load() != null) {
        await ApiClient.instance.post('/notifications/device-token/remove', body: {'token': token});
      }
    } catch (_) {
      // Logout should still complete when the network is unavailable.
    }
  }
}
