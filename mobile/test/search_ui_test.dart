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
  _SearchApi({this.studentRecordCount = 1, this.coachRecordCount = 0});

  final int studentRecordCount;
  final int coachRecordCount;
  final String today = DateTime.now().toIso8601String().substring(0, 10);
  final attendanceSearchRequests = <Uri>[];

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    final Object body;
    switch (request.url.path) {
      case '/attendance/daily-missing':
      case '/coaches/7/attendance':
        body = <dynamic>[];
      case '/attendance/coaches':
        body = List.generate(
          coachRecordCount,
          (index) => {
            'id': 100 + index,
            'coach_id': 5,
            'coach_name':
                coachRecordCount == 1 ? 'Coach One' : 'Coach One ${index + 1}',
            'date': today,
            'status': 'PRESENT',
            'entry_time': '${today}T09:00:00',
            'exit_time': '${today}T10:00:00',
          },
        );
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
        if (request.url.queryParameters.containsKey('search')) {
          attendanceSearchRequests.add(request.url);
          body = [
            {
              ..._attendanceRecord(),
              'class_date': '2024-02-03',
              'timestamp': '2024-02-03T09:30:00',
            }
          ];
        } else {
          body = List.generate(
            studentRecordCount,
            (index) => {
              ..._attendanceRecord(),
              'id': 9 + index,
              'student_name': studentRecordCount == 1
                  ? 'Maya Sharma'
                  : 'Maya Sharma ${index + 1}',
            },
          );
        }
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
    await tester.scrollUntilVisible(
      find.text('All Attendance Records'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await _enterSearch(
      tester,
      'maya yoga',
      hintText: 'Student, activity, coach, date, or status',
    );
    expect(find.text('Maya Sharma'), findsWidgets);

    await _enterSearch(
      tester,
      'maya ballet',
      hintText: 'Student, activity, coach, date, or status',
    );
    expect(find.text('No results found.'), findsOneWidget);
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

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
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
    expect(studentSearch, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toggle-all-student-attendance')),
        matching: find.text('Show'),
      ),
      findsOneWidget,
    );

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
    expect(coachEmptyState, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toggle-coach-attendance')),
        matching: find.text('Show'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Admin attendance filters remain in one sticky toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi(studentRecordCount: 16).install();
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
    final studentFiltersButton =
        find.byKey(const ValueKey('toggle-student-attendance-filters'));
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('All activities'), findsNothing);
    expect(find.textContaining('Approve filtered pending'), findsNothing);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(studentSearch, findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('All activities'), findsNothing);

    await tester.ensureVisible(studentFiltersButton);
    await tester.tap(studentFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All activities'), findsOneWidget);
    expect(find.text('All statuses'), findsOneWidget);
    expect(find.text('All reviews'), findsOneWidget);
    expect(find.text('All review states'), findsNothing);
    expect(find.textContaining('Approve filtered pending'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(studentSearch, findsOneWidget);
    expect(find.text('All activities'), findsOneWidget);
    expect(find.text('All statuses'), findsOneWidget);
    expect(find.text('All reviews'), findsOneWidget);

    await tester.enterText(studentSearch, 'Maya');
    await tester.pump();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.byTooltip('Clear 1 active filter'), findsOneWidget);

    await tester.ensureVisible(studentFiltersButton);
    await tester.tap(studentFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All activities'), findsNothing);
    expect(find.text('Filters (1)'), findsOneWidget);
    await tester.tap(studentFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All activities'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });

  testWidgets('Coach attendance filters remain in one sticky toolbar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi(coachRecordCount: 16).install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-attendance-section')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final coachSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Coach or date',
    );
    expect(coachSearch, findsOneWidget);
    final coachFiltersButton =
        find.byKey(const ValueKey('toggle-coach-attendance-filters'));
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('All coaches'), findsNothing);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(coachSearch, findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('All coaches'), findsNothing);

    await tester.ensureVisible(coachFiltersButton);
    await tester.tap(coachFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All coaches'), findsOneWidget);
    expect(find.text('All statuses'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(coachSearch, findsOneWidget);
    expect(find.text('All coaches'), findsOneWidget);
    expect(find.text('All statuses'), findsOneWidget);

    await tester.enterText(coachSearch, 'Coach One');
    await tester.pump();
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.byTooltip('Clear 1 active filter'), findsOneWidget);

    await tester.ensureVisible(coachFiltersButton);
    await tester.tap(coachFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All coaches'), findsNothing);
    expect(find.text('Filters (1)'), findsOneWidget);
    await tester.tap(coachFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All coaches'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });

  testWidgets('Attendance toolbars fit a narrow phone viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();

    final studentFiltersButton =
        find.byKey(const ValueKey('toggle-student-attendance-filters'));
    await tester.scrollUntilVisible(
      studentFiltersButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(studentFiltersButton, findsOneWidget);
    expect(find.text('All activities'), findsNothing);
    await tester.tap(studentFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All activities'), findsOneWidget);
    expect(find.textContaining('Approve filtered pending'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final coachFiltersButton =
        find.byKey(const ValueKey('toggle-coach-attendance-filters'));
    await tester.scrollUntilVisible(
      coachFiltersButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(coachFiltersButton, findsOneWidget);
    expect(find.text('All coaches'), findsNothing);
    await tester.tap(coachFiltersButton);
    await tester.pumpAndSettle();
    expect(find.text('All coaches'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('coach-search-toolbar')),
        matching: find.text('All statuses'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin Attendance has one sticky manual entry action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi().install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Manual Entry'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Student attendance'), findsOneWidget);
    expect(find.text('Coach attendance'), findsOneWidget);
  });

  testWidgets('Admin calendar details do not duplicate sticky searches',
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
      find.text('No coach attendance marked on this date.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Student, activity, coach, status, or approval',
      ),
      findsNothing,
    );
    expect(find.text('All statuses'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Coaches Missing Attendance Today'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search coach, activity, or date',
      ),
      findsNothing,
    );
    expect(find.text('Coaches Missing Attendance Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Student and coach attendance headings stay sticky per section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    _SearchApi(studentRecordCount: 18, coachRecordCount: 18).install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AdminAttendanceTab()),
    ));
    await tester.pumpAndSettle();

    final studentHeading =
        find.byKey(const ValueKey('student-section-heading'));
    await tester.scrollUntilVisible(
      find.text('All Attendance Records'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(studentHeading, findsOneWidget);
    final studentTitle = find.descendant(
      of: studentHeading,
      matching: find.text('Student Attendance'),
    );
    expect(tester.getTopLeft(studentTitle).dy, lessThan(60));

    final coachHeading = find.byKey(const ValueKey('coach-section-heading'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coach-attendance-section')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(coachHeading, findsOneWidget);
    final coachTitle = find.descendant(
      of: coachHeading,
      matching: find.text('Coach Attendance'),
    );
    expect(tester.getTopLeft(coachTitle).dy, lessThan(80));
    expect(
      studentHeading.evaluate().isEmpty ||
          tester.getTopLeft(studentTitle).dy < 0,
      isTrue,
    );
    expect(tester.takeException(), isNull);
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

    await tester.scrollUntilVisible(
      find.text('Student Attendance'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _enterSearch(tester, 'maya not confirm');
    expect(find.text('Maya Sharma'), findsOneWidget);

    await _enterSearch(tester, 'maya ballet');
    expect(find.text('No student attendance matches this search.'),
        findsOneWidget);
  });

  testWidgets('Coach attendance search can span all dates', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _SearchApi();
    api.install();
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
    await tester.scrollUntilVisible(
      find.text('All dates'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('All dates'));
    await tester.pumpAndSettle();
    await _enterSearch(tester, 'maya');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(api.attendanceSearchRequests, hasLength(1));
    expect(
        api.attendanceSearchRequests.single.queryParameters['search'], 'maya');
    expect(api.attendanceSearchRequests.single.queryParameters,
        isNot(contains('date_from')));
    expect(api.attendanceSearchRequests.single.queryParameters,
        isNot(contains('date_to')));
    expect(find.text('2024-02-03'), findsOneWidget);
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
