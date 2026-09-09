import 'api_client.dart';
import 'auth_storage.dart';
import 'notification_polling_service.dart';

class AuthApi {
  static Future<AuthSession> login(String email, String password) async {
    final data = await ApiClient.instance.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    ) as Map<String, dynamic>;

    final session = AuthSession(
      userId: data['user_id'] as int,
      name: data['name'] as String,
      role: data['role'] as String,
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
    await AuthStorage.save(session);
    return session;
  }

  static Future<void> logout() async {
    try {
      await ApiClient.instance.post('/auth/logout');
    } catch (_) {
      // best-effort; clear local session regardless
    }
    await AuthStorage.clear();
    await NotificationPollingService.resetOnLogout();
  }

  static Future<void> forgotPassword(String email) async {
    await ApiClient.instance.post('/auth/forgot-password', body: {'email': email}, auth: false);
  }

  static Future<void> resetPassword(String token, String newPassword) async {
    await ApiClient.instance.post(
      '/auth/reset-password',
      body: {'token': token, 'new_password': newPassword},
      auth: false,
    );
  }
}
