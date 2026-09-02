import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  final int userId;
  final String name;
  final String role; // ADMIN, COACH, STUDENT
  final String accessToken;
  final String refreshToken;

  AuthSession({
    required this.userId,
    required this.name,
    required this.role,
    required this.accessToken,
    required this.refreshToken,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'role': role,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        userId: json['userId'] as int,
        name: json['name'] as String,
        role: json['role'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

class AuthStorage {
  static const _key = 'vimj_auth_session';

  static Future<void> save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
  }

  static Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateAccessToken(String accessToken) async {
    final session = await load();
    if (session == null) return;
    await save(AuthSession(
      userId: session.userId,
      name: session.name,
      role: session.role,
      accessToken: accessToken,
      refreshToken: session.refreshToken,
    ));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
