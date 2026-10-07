import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_storage.dart';

class AdminAttendanceListVisibility {
  const AdminAttendanceListVisibility({
    required this.showStudentAttendanceRecords,
    required this.showCoachAttendanceRecords,
  });

  final bool showStudentAttendanceRecords;
  final bool showCoachAttendanceRecords;

  static const expanded = AdminAttendanceListVisibility(
    showStudentAttendanceRecords: true,
    showCoachAttendanceRecords: true,
  );

  factory AdminAttendanceListVisibility.fromJson(Map<String, dynamic> json) =>
      AdminAttendanceListVisibility(
        showStudentAttendanceRecords:
            json['show_student_attendance_records'] as bool? ?? true,
        showCoachAttendanceRecords:
            json['show_coach_attendance_records'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'show_student_attendance_records': showStudentAttendanceRecords,
        'show_coach_attendance_records': showCoachAttendanceRecords,
      };
}

class AdminAttendanceVisibilityStore {
  static const _path = '/attendance/list-visibility';
  static const _studentKey = 'admin_show_all_student_attendance_records';
  static const _coachKey = 'admin_show_coach_attendance_records';

  String _accountKey(String key, int userId) => '${key}_user_$userId';
  String _pendingKey(int userId) =>
      'admin_attendance_list_visibility_sync_pending_user_$userId';

  Future<AdminAttendanceListVisibility> load() async {
    final preferences = await SharedPreferences.getInstance();
    final session = await AuthStorage.load();
    if (session == null || session.role.toUpperCase() != 'ADMIN') {
      return _readLocal(preferences);
    }

    final userId = session.userId;
    final local = _readLocal(preferences, userId: userId);
    final hasLocal = _hasLocal(preferences, userId);
    final pending = preferences.getBool(_pendingKey(userId)) ?? false;

    if (pending && hasLocal) {
      try {
        final saved = await _saveRemote(local);
        await _writeLocal(preferences, saved, userId: userId, pending: false);
        await _removeLegacyValues(preferences);
        return saved;
      } catch (_) {
        return local;
      }
    }

    try {
      final data = await ApiClient.instance.get(_path) as Map<String, dynamic>;
      if (data['configured'] == true) {
        final remote = AdminAttendanceListVisibility.fromJson(data);
        await _writeLocal(preferences, remote, userId: userId, pending: false);
        await _removeLegacyValues(preferences);
        return remote;
      }

      if (hasLocal) {
        await _writeLocal(preferences, local, userId: userId, pending: true);
        try {
          final saved = await _saveRemote(local);
          await _writeLocal(preferences, saved, userId: userId, pending: false);
          await _removeLegacyValues(preferences);
          return saved;
        } catch (_) {
          return local;
        }
      }
      return AdminAttendanceListVisibility.expanded;
    } catch (_) {
      return local;
    }
  }

  Future<void> save(AdminAttendanceListVisibility visibility) async {
    await cacheLocal(visibility);
    try {
      await syncRemote(visibility);
    } catch (_) {
      // Keep the local value and pending marker so a later screen open can retry.
    }
  }

  Future<void> cacheLocal(AdminAttendanceListVisibility visibility) async {
    final preferences = await SharedPreferences.getInstance();
    final session = await AuthStorage.load();
    if (session == null || session.role.toUpperCase() != 'ADMIN') {
      await preferences.setBool(
          _studentKey, visibility.showStudentAttendanceRecords);
      await preferences.setBool(
          _coachKey, visibility.showCoachAttendanceRecords);
      return;
    }

    final userId = session.userId;
    await _writeLocal(preferences, visibility, userId: userId, pending: true);
  }

  Future<void> syncRemote(AdminAttendanceListVisibility visibility) async {
    final preferences = await SharedPreferences.getInstance();
    final session = await AuthStorage.load();
    if (session == null || session.role.toUpperCase() != 'ADMIN') return;

    final saved = await _saveRemote(visibility);
    await _writeLocal(preferences, saved,
        userId: session.userId, pending: false);
    await _removeLegacyValues(preferences);
  }

  AdminAttendanceListVisibility _readLocal(
    SharedPreferences preferences, {
    int? userId,
  }) {
    final student = userId == null
        ? preferences.getBool(_studentKey)
        : preferences.getBool(_accountKey(_studentKey, userId)) ??
            preferences.getBool(_studentKey);
    final coach = userId == null
        ? preferences.getBool(_coachKey)
        : preferences.getBool(_accountKey(_coachKey, userId)) ??
            preferences.getBool(_coachKey);
    return AdminAttendanceListVisibility(
      showStudentAttendanceRecords: student ?? true,
      showCoachAttendanceRecords: coach ?? true,
    );
  }

  bool _hasLocal(SharedPreferences preferences, int userId) =>
      preferences.containsKey(_accountKey(_studentKey, userId)) ||
      preferences.containsKey(_accountKey(_coachKey, userId)) ||
      preferences.containsKey(_studentKey) ||
      preferences.containsKey(_coachKey);

  Future<void> _writeLocal(
    SharedPreferences preferences,
    AdminAttendanceListVisibility visibility, {
    required int userId,
    required bool pending,
  }) async {
    await preferences.setBool(
      _accountKey(_studentKey, userId),
      visibility.showStudentAttendanceRecords,
    );
    await preferences.setBool(
      _accountKey(_coachKey, userId),
      visibility.showCoachAttendanceRecords,
    );
    await preferences.setBool(_pendingKey(userId), pending);
  }

  Future<void> _removeLegacyValues(SharedPreferences preferences) async {
    await preferences.remove(_studentKey);
    await preferences.remove(_coachKey);
  }

  Future<AdminAttendanceListVisibility> _saveRemote(
    AdminAttendanceListVisibility visibility,
  ) async {
    final data = await ApiClient.instance.put(_path, body: visibility.toJson())
        as Map<String, dynamic>;
    return AdminAttendanceListVisibility.fromJson(data);
  }
}
