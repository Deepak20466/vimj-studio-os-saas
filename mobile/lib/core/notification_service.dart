import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (on-device) notifications — used to surface reminders and updates
/// fetched from the backend while the app is open. Full push delivery when
/// the app is closed requires wiring a Firebase project (FCM) into this
/// plugin's Android/iOS channels; that project-specific setup is outside
/// what this codebase can provide out of the box. SMS/WhatsApp reminders are
/// sent directly by the backend (see backend/app/services/notifications.py)
/// and work regardless of push setup.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(settings);
    _initialized = true;

    // Android 13+ (API 33) requires this runtime prompt — declaring
    // POST_NOTIFICATIONS in the manifest alone is not enough there; without
    // this, `show()` below silently does nothing on those devices, with no
    // error anywhere to indicate why.
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  static Future<void> show({required int id, required String title, required String body}) async {
    if (!_initialized) await init();
    const androidDetails = AndroidNotificationDetails(
      'vimj_general',
      'VIMJ Studio Updates',
      channelDescription: 'Fee reminders, leave decisions, and attendance alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());
    await _plugin.show(id, title, body, details);
  }
}
