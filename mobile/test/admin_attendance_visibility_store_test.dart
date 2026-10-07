import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/admin_attendance_visibility_store.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> signInAsAdmin(int userId) => AuthStorage.save(AuthSession(
        userId: userId,
        name: 'Admin',
        role: 'ADMIN',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ));

  test('loads saved visibility from the admin account', () async {
    await signInAsAdmin(12);
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/attendance/list-visibility');
      return http.Response(
        jsonEncode({
          'show_student_attendance_records': false,
          'show_coach_attendance_records': true,
          'configured': true,
        }),
        200,
      );
    }));

    final visibility = await AdminAttendanceVisibilityStore().load();

    expect(visibility.showStudentAttendanceRecords, isFalse);
    expect(visibility.showCoachAttendanceRecords, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
        preferences
            .getBool('admin_show_all_student_attendance_records_user_12'),
        isFalse);
  });

  test('migrates previous device-local choices to the account', () async {
    SharedPreferences.setMockInitialValues({
      'admin_show_all_student_attendance_records': false,
      'admin_show_coach_attendance_records': true,
    });
    await signInAsAdmin(12);
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'show_student_attendance_records': true,
            'show_coach_attendance_records': true,
            'configured': false,
          }),
          200,
        );
      }
      expect(request.method, 'PUT');
      expect(jsonDecode(request.body), {
        'show_student_attendance_records': false,
        'show_coach_attendance_records': true,
      });
      return http.Response(
        jsonEncode({
          'show_student_attendance_records': false,
          'show_coach_attendance_records': true,
          'configured': true,
        }),
        200,
      );
    }));

    final visibility = await AdminAttendanceVisibilityStore().load();

    expect(visibility.showStudentAttendanceRecords, isFalse);
    expect(visibility.showCoachAttendanceRecords, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('admin_show_all_student_attendance_records'),
        isFalse);
    expect(
      preferences
          .getBool('admin_attendance_list_visibility_sync_pending_user_12'),
      isFalse,
    );
  });

  test('retries a local change saved while offline on the next load', () async {
    await signInAsAdmin(12);
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      return http.Response('{"detail":"offline"}', 503);
    }));
    final store = AdminAttendanceVisibilityStore();
    await store.load();
    await store.save(const AdminAttendanceListVisibility(
      showStudentAttendanceRecords: false,
      showCoachAttendanceRecords: false,
    ));

    var uploaded = false;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      expect(request.method, 'PUT');
      uploaded = true;
      return http.Response(
        jsonEncode({
          'show_student_attendance_records': false,
          'show_coach_attendance_records': false,
          'configured': true,
        }),
        200,
      );
    }));
    final visibility = await store.load();

    expect(uploaded, isTrue);
    expect(visibility.showStudentAttendanceRecords, isFalse);
    expect(visibility.showCoachAttendanceRecords, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences
          .getBool('admin_attendance_list_visibility_sync_pending_user_12'),
      isFalse,
    );
  });
}
