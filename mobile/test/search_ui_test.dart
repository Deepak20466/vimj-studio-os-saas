import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/features/admin/admin_attendance_tab.dart';
import 'package:vimj_attendance/features/coach/coach_facility_attendance_tab.dart';
import 'package:vimj_attendance/features/shared/session_photo_gallery.dart';

class _SearchApi {
  final String today = DateTime.now().toIso8601String().substring(0, 10);

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    final Object body;
    switch (request.url.path) {
      case '/attendance/daily-missing':
      case '/attendance/coaches':
      case '/coaches/7/attendance':
        body = <dynamic>[];
      case '/activities':
        body = [
          {'id': 12, 'name': 'Yoga', 'capacity': 20, 'monthly_fee': '100'}
        ];
      case '/coaches':
        body = [
          {
            'id': 5,
            'name': 'Coach One',
            'email': 'coach@example.test',
            'is_active': true,
          }
        ];
      case '/attendance/students':
        body = [_attendanceRecord()];
      case '/activities/session-photos':
        body = [
          {
            'class_id': 41,
            'date': today,
            'start_time': '09:00',
            'end_time': '10:00',
            'uploaded_at': '${today}T10:05:00',
            'activity_name': 'Yoga',
            'coach_name': 'Coach One',
          }
        ];
      default:
        body = {'detail': 'Unexpected test request: ${request.url.path}'};
    }

    return http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _attendanceRecord() => {
        'id': 9,
        'student_id': 1,
        'student_name': 'Maya Sharma',
        'class_id': 41,
        'activity_id': 12,
        'activity_name': 'Yoga',
        'coach_id': 7,
        'coach_name': 'Coach One',
        'status': 'NOT_CONFIRM',
        'class_date': today,
        'timestamp': '${today}T09:30:00',
        'marked_manually': false,
        'has_selfie': false,
        'approval_status': 'PENDING',
      };
}

Future<void> _enterSearch(
  WidgetTester tester,
  String query, {
  String? hintText,
}) async {
  final searchField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Search attendance' &&
        (hintText == null || widget.decoration?.hintText == hintText),
  );
  expect(searchField, findsOneWidget);
  await tester.ensureVisible(searchField);
  await tester.enterText(searchField, query);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Admin attendance searches across student and activity details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();

    await _enterSearch(
      tester,
      'maya yoga',
      hintText: 'Student, activity, coach, status, or approval',
    );
    expect(find.text('Maya Sharma'), findsWidgets);

    await _enterSearch(
      tester,
      'maya ballet',
      hintText: 'Student, activity, coach, status, or approval',
    );
    expect(find.text('No student attendance matches these filters.'),
        findsOneWidget);
  });

  testWidgets('Admin attendance record lists can be hidden independently',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('All Attendance Records'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final studentSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Student, activity, coach, date, or status',
    );
    expect(studentSearch, findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('toggle-all-student-attendance')));
    await tester.pumpAndSettle();
    expect(studentSearch, findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('toggle-all-student-attendance')));
    await tester.pumpAndSettle();
    expect(studentSearch, findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-attendance-section')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final coachEmptyState =
        find.text('No coach attendance records match these filters.');
    expect(coachEmptyState, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toggle-coach-attendance')));
    await tester.pumpAndSettle();
    expect(coachEmptyState, findsNothing);
  });

  testWidgets('Coach attendance searches the selected day details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await AuthStorage.save(AuthSession(
      userId: 7,
      name: 'Coach One',
      role: 'COACH',
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
    ));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: CoachFacilityAttendanceTab()),
    ));
    await tester.pumpAndSettle();

    await _enterSearch(tester, 'maya not confirm');
    expect(find.text('Maya Sharma'), findsOneWidget);

    await _enterSearch(tester, 'maya ballet');
    expect(find.text('No student attendance matches this search.'),
        findsOneWidget);
  });

  testWidgets('Session photo gallery matches multiple search terms',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const SessionPhotoGallery(),
    ));
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search activity, coach, or date',
    );
    await tester.enterText(searchField, 'yoga coach one');
    await tester.pump();
    expect(find.textContaining('Yoga'), findsOneWidget);

    await tester.enterText(searchField, 'ballet coach');
    await tester.pump();
    expect(find.text('No photos match the search or date filter.'),
        findsOneWidget);
  });
}
