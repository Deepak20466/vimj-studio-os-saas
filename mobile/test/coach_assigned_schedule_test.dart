import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/features/coach/coach_dashboard_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coach dashboard shows the admin-assigned recurring schedule',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final today = DateTime.now();
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final schedule = {
      'id': 12,
      'activity_id': 3,
      'coach_id': 7,
      'location': 'Studio',
      'session_period': 'EVENING',
      'start_time': '18:00:00',
      'end_time': '19:00:00',
      'days_of_week': [weekdays[today.weekday - 1]],
      'active_months': [today.month],
      'is_active': true,
    };
    final requests = <String>[];
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      requests.add(request.url.path);
      if (request.url.path == '/activities/classes/my') {
        return http.Response('[]', 200);
      }
      if (request.url.path == '/batches/my') {
        return http.Response(jsonEncode([schedule]), 200);
      }
      if (request.url.path == '/coaches/7/attendance') {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 404);
    }));
    await AuthStorage.save(AuthSession(
      userId: 7,
      name: 'Coach User',
      role: 'COACH',
      accessToken: 'test-token',
      refreshToken: 'test-refresh-token',
    ));

    await tester.pumpWidget(const MaterialApp(home: CoachDashboardTab()));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requests, contains('/batches/my'));
    expect(find.text('Assigned schedule · Activity #3'), findsOneWidget);
    expect(find.text('18:00:00 - 19:00:00'), findsOneWidget);
  });
}
