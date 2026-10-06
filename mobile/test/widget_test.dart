import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/features/auth/login_screen.dart';

class _AttendanceApi {
  final requests = <http.Request>[];
  final delayedFeeStatus = Completer<http.Response>();
  final delayedClassSummary = Completer<http.Response>();
  bool holdFeeStatus = false;
  bool holdClassSummary = false;

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;

    if (path == '/auth/login') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final role =
          (body['email'] as String).startsWith('admin') ? 'ADMIN' : 'COACH';
      return _json({
        'user_id': role == 'ADMIN' ? 1 : 7,
        'name': role == 'ADMIN' ? 'Admin User' : 'Coach User',
        'role': role,
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
      });
    }

    if (path == '/dashboard/summary') {
      return _json({
        'total_students': 27,
        'total_coaches': 4,
        'total_classes_this_month': 50,
        'monthly_revenue': 12000,
        'unpaid_fees_count': 2,
      });
    }
    if (path == '/dashboard/fee-status') {
      if (holdFeeStatus) return delayedFeeStatus.future;
      return _json({'paid': 20, 'unpaid': 3, 'overdue': 1});
    }
    if (path == '/attendance/daily-missing') return _json([]);
    if (path == '/dashboard/activity-attendance') {
      return _json({
        'points': [
          {'activity_name': 'Dance', 'avg_attendance_pct': 85}
        ]
      });
    }
    if (path == '/dashboard/revenue') {
      return _json({
        'fee_revenue': 10000,
        'product_revenue': 2000,
        'total_revenue': 12000,
      });
    }
    if (path == '/activities/classes/my') {
      return _json([
        {
          'id': 42,
          'activity_id': 3,
          'coach_id': 7,
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'start_time': '10:00',
          'end_time': '11:00',
          'has_group_photo': false,
        }
      ]);
    }
    if (path == '/coaches/7/attendance') return _json([]);
    if (path == '/activities/classes/42/summary') {
      if (holdClassSummary) return delayedClassSummary.future;
      return _json({
        'enrolled_count': 8,
        'marked_count': 6,
        'fee_paid_count': 5,
        'fee_unpaid_count': 3,
      });
    }
    if (path == '/attendance/coach-mark' && request.method == 'POST') {
      return _json({'status': 'PRESENT'});
    }

    return _json(
        {'detail': 'Unexpected test request: ${request.method} $path'}, 404);
  }

  static http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: const {'content-type': 'application/json'},
      );
}

Future<void> _signIn(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), 'password123');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsAtLeastNWidgets(1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'Admin can sign in, load summary progressively, and change revenue period',
      (tester) async {
    final api = _AttendanceApi()..holdFeeStatus = true;
    api.install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const LoginScreen(),
    ));

    await _signIn(tester, 'admin@example.test');
    await _pumpUntil(tester, find.text('Dashboard'));
    await _pumpUntil(tester, find.text('27'));

    // The main dashboard is interactive while the independent fee request is held.
    expect(
        api.requests.any((r) => r.url.path == '/dashboard/fee-status'), isTrue);
    api.delayedFeeStatus.complete(_AttendanceApi._json(
      {'paid': 20, 'unpaid': 3, 'overdue': 1},
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Overall'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Overall'));
    await tester.pumpAndSettle();
    expect(
      api.requests.any((r) =>
          r.url.path == '/dashboard/revenue' &&
          r.url.queryParameters['period'] == 'overall'),
      isTrue,
    );
  });

  testWidgets(
      'Coach can sign in, see classes before summaries, and mark attendance',
      (tester) async {
    final api = _AttendanceApi()..holdClassSummary = true;
    api.install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const LoginScreen(),
    ));

    await _signIn(tester, 'coach@example.test');
    await _pumpUntil(tester, find.text("Today's Classes"));
    await _pumpUntil(tester, find.text('10:00 - 11:00'));
    expect(find.text('Loading class details...'), findsOneWidget);

    await tester.tap(find.text('Present'));
    await tester.pump();
    final submit = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit'),
    );
    expect(submit.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    for (var i = 0;
        i < 20 &&
            !api.requests
                .any((request) => request.url.path == '/attendance/coach-mark');
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final markRequest = api.requests.singleWhere(
      (request) => request.url.path == '/attendance/coach-mark',
      orElse: () => throw StateError(
        'No coach attendance request. Requests: ${api.requests.map((r) => '${r.method} ${r.url.path}').join(', ')}',
      ),
    );
    expect(markRequest.method, 'POST');
    expect(jsonDecode(markRequest.body), {'status': 'PRESENT'});

    api.delayedClassSummary.complete(_AttendanceApi._json({
      'enrolled_count': 8,
      'marked_count': 6,
      'fee_paid_count': 5,
      'fee_unpaid_count': 3,
    }));
    for (var i = 0;
        i < 20 && find.text('Loading class details...').evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Loading class details...'), findsNothing);
  });
}
