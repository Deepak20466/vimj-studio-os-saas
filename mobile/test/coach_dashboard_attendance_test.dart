import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/features/coach/coach_dashboard_tab.dart';

/// Minimal fake backend for the coach dashboard's "My Attendance Today" card.
class _FakeBackend {
  int attendanceCalls = 0;
  bool attendanceFails = false;
  final attendanceRows = <Map<String, dynamic>>[];

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    final headers = {'content-type': 'application/json'};
    if (path == '/coaches/7/attendance') {
      attendanceCalls++;
      if (attendanceFails) {
        return http.Response('{"detail":"Forbidden"}', 403, headers: headers);
      }
      return http.Response(jsonEncode(attendanceRows), 200, headers: headers);
    }
    return http.Response(jsonEncode(<dynamic>[]), 200, headers: headers);
  }
}

Future<void> _setCoachSession() async {
  SharedPreferences.setMockInitialValues({});
  await AuthStorage.save(AuthSession(
    userId: 7,
    name: 'Test Coach',
    role: 'COACH',
    accessToken: 'local-widget-test-token',
    refreshToken: 'local-widget-test-refresh',
  ));
}

String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

void main() {
  setUp(_setCoachSession);

  testWidgets('a failed attendance check shows Retry that re-checks',
      (tester) async {
    final api = _FakeBackend()..attendanceFails = true;
    api.install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const CoachDashboardTab(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Present'), findsNothing);

    api.attendanceFails = false;
    final before = api.attendanceCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.attendanceCalls, greaterThan(before));
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Present'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('admin-recorded attendance appears without a manual refresh',
      (tester) async {
    final api = _FakeBackend()..install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const CoachDashboardTab(),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Not marked yet: the coach still sees the mark buttons.
    expect(find.text('Present'), findsOneWidget);

    // Admin records today's attendance for this coach on the backend.
    api.attendanceRows.add({
      'id': 9,
      'coach_id': 7,
      'date': '${_today()}T00:00:00',
      'entry_time': null,
      'exit_time': null,
      'status': 'ABSENT',
    });

    // The background refresh runs every 30 seconds.
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Absent — locked'), findsOneWidget);
    expect(find.text('Present'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
