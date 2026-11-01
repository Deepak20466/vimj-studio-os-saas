import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications used to display FCM messages while the app is open.
/// Messages delivered while the app is backgrounded or closed are displayed
/// directly by Android through Firebase Cloud Messaging.
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
