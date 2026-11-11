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
  final delayedInsights = Completer<http.Response>();
  final delayedClassSummary = Completer<http.Response>();
  bool holdInsights = false;
  bool holdClassSummary = false;

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;

    if (path == '/health') return _json({'status': 'ok'});

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

    if (path == '/insights/revenue-risk') {
      if (holdInsights) return delayedInsights.future;
      return _insights();
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

  static http.Response _insights() => _json({
        'risks': <dynamic>[],
        'forecast': {
          'next_month_revenue': 12000,
          'monthly_collections': <dynamic>[],
          'months_used': <dynamic>[],
        },
        'summary': {'total_at_risk': 0},
        'kpis': {
          'total_students': 27,
          'today_present': 20,
          'fee_pending_amount': 3000,
        },
        'batch_analytics': {
          'most_profitable_batch': null,
          'attendance_drop_batches': <dynamic>[],
          'total_revenue_at_risk': 0,
          'batches': <dynamic>[],
        },
      });
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

Finder _dashboardScrollable() {
  final refresh = find.byType(RefreshIndicator).first;
  final listView =
      find.descendant(of: refresh, matching: find.byType(ListView)).first;
  return find.descendant(of: listView, matching: find.byType(Scrollable)).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login credentials stay legible in dark mode', (tester) async {
    final api = _AttendanceApi();
    api.install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const LoginScreen(),
    ));
    await tester.pump();

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    final decorations =
        tester.widgetList<InputDecorator>(find.byType(InputDecorator)).toList();
    expect(fields[0].style?.color, AppColors.text);
    expect(fields[1].style?.color, AppColors.text);
    expect(decorations[0].decoration.fillColor, Colors.white);
    expect(decorations[1].decoration.fillColor, Colors.white);
    expect(
        api.requests.any((request) => request.url.path == '/health'), isTrue);
  });

  testWidgets(
      'Admin can sign in, render while insights load, and select AI period',
      (tester) async {
    final api = _AttendanceApi()..holdInsights = true;
    api.install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const LoginScreen(),
    ));

    await _signIn(tester, 'admin@example.test');
    await _pumpUntil(tester, find.text('Dashboard'));
    await _pumpUntil(tester, find.text('Admin AI Command Center'));

    // Revenue is an independent section and stays interactive while insights load.
    expect(api.requests.any((r) => r.url.path == '/insights/revenue-risk'),
        isTrue);
    expect(api.requests.any((r) => r.url.path == '/dashboard/revenue'), isTrue);
    final aiOverall = find.widgetWithText(ChoiceChip, 'Overall').first;
    await tester.ensureVisible(aiOverall);
    await tester.pumpAndSettle();
    await tester.tap(aiOverall);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      api.requests.any((r) =>
          r.url.path == '/insights/revenue-risk' &&
          r.url.queryParameters['period'] == 'overall'),
      isTrue,
    );

    api.delayedInsights.complete(_AttendanceApi._insights());
    await tester.pumpAndSettle();
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
