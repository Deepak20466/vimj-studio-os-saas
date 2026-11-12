import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/features/admin/admin_home.dart';
import 'package:vimj_attendance/features/admin/admin_salary_tab.dart';
import 'package:vimj_attendance/features/coach/coach_home.dart';
import 'package:vimj_attendance/features/coach/coach_salary_tab.dart';

class _ScreenApi {
  final requests = <http.Request>[];
  final salaryRows = <Map<String, dynamic>>[];
  final sharedFiles = <Map<dynamic, dynamic>>[];

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getTemporaryDirectory'
          ? Directory.systemTemp.path
          : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        if (call.arguments is Map) {
          sharedFiles.add(Map<dynamic, dynamic>.from(call.arguments as Map));
        }
        return 'success';
      },
    );
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    Object body = <dynamic>[];
    var statusCode = 200;

    if (path == '/dashboard/summary') {
      body = {
        'total_students': 8,
        'total_coaches': 3,
        'total_classes_this_month': 39,
        'monthly_revenue': 1000,
        'unpaid_fees_count': 2,
      };
    } else if (path == '/dashboard/fee-status') {
      body = {'paid': 5, 'unpaid': 2, 'overdue': 1};
    } else if (path == '/dashboard/activity-attendance') {
      body = {'points': <dynamic>[]};
    } else if (path == '/dashboard/revenue') {
      body = {
        'fee_revenue': 1000,
        'product_revenue': 0,
        'total_revenue': 1000,
      };
    } else if (path == '/insights/revenue-risk') {
      body = {
        'risks': <dynamic>[],
        'forecast': {
          'next_month_revenue': 1000,
          'monthly_collections': <dynamic>[],
          'months_used': <dynamic>[],
        },
        'summary': {'total_at_risk': 0},
        'kpis': {
          'total_students': 8,
          'today_present': 2,
          'fee_pending_amount': 0
        },
        'batch_analytics': {
          'most_profitable_batch': null,
          'attendance_drop_batches': <dynamic>[],
          'total_revenue_at_risk': 0,
          'batches': <dynamic>[],
        },
      };
    } else if (path == '/coaches') {
      body = [
        {
          'id': 8,
          'name': 'Smoke Test Coach',
          'email': 'coach@example.test',
          'phone': null,
          'is_active': true,
        }
      ];
    } else if (path == '/salary' && request.method == 'POST') {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      salaryRows.add({
        'id': salaryRows.length + 1,
        'coach_id': payload['coach_id'],
        'coach_name': 'Smoke Test Coach',
        'month': payload['month'],
        'year': payload['year'],
        'amount': payload['amount'].toString(),
        'notified_at': null,
        'acknowledged_date': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      statusCode = 201;
      body = salaryRows.last;
    } else if (path == '/salary' && request.method == 'GET') {
      body = salaryRows;
    } else if (path == '/salary/export') {
      final isPdf = request.url.queryParameters['fmt'] == 'pdf';
      return http.Response.bytes(
        isPdf ? const [37, 80, 68, 70, 45] : utf8.encode('month,year,amount\n'),
        statusCode,
        headers: {
          'content-type': isPdf ? 'application/pdf' : 'text/csv',
        },
      );
    } else if (path == '/salary/coach/7') {
      body = [
        {
          'id': 1,
          'month': 11,
          'year': 2026,
          'amount': '25000',
          'notified_at': null,
          'acknowledged_date': null,
          'created_at': DateTime.now().toIso8601String(),
        }
      ];
    } else if (path == '/reports') {
      body = {
        'total_revenue': 1000,
        'product_revenue': 0,
        'revenue_basis': 'Paid fees',
        'classes_done': 2,
        'fee_paid_total': 1000,
        'fee_pending_total': 0,
        'activities': <dynamic>[],
        'unassigned_revenue': 0,
      };
    } else if (path == '/batches/coverage') {
      body = {
        'unassigned_batches': <dynamic>[],
        'batches_not_generated_today': <dynamic>[],
        'activity_coach_map': <dynamic>[],
      };
    } else if (path == '/academy') {
      body = {
        'name': 'VIMJ Studio',
        'phone': '',
        'email': '',
        'address': '',
        'description': '',
      };
    } else if (path == '/auth/me') {
      body = {
        'id': 7,
        'user_id': 7,
        'name': 'Test Coach',
        'email': 'coach@example.test',
        'phone': '',
        'role': 'COACH',
        'is_active': true,
      };
    } else if (path == '/fees/my') {
      body = [
        {
          'id': 901,
          'student_id': 11,
          'student_name': 'Assigned Student',
          'month': 11,
          'year': 2026,
          'amount': '150.00',
          'product_amount': '25.00',
          'balance_amount': '175.00',
          'status': 'UNPAID',
          'due_date': '2026-11-10',
        }
      ];
    } else if (path == '/notifications') {
      body = {'items': <dynamic>[]};
    }

    return http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Future<void> _setRole(String role) async {
  await AuthStorage.save(AuthSession(
    userId: role == 'ADMIN' ? 1 : 7,
    name: role == 'ADMIN' ? 'Test Admin' : 'Test Coach',
    role: role,
    accessToken: 'local-widget-test-token',
    refreshToken: 'local-widget-test-refresh',
  ));
}

Future<void> _tapAdminSection(
    WidgetTester tester, int index, String title) async {
  await tester.tap(find.byType(NavigationDestination).at(index));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text(title), findsWidgets);
}

Finder _dashboardScrollable() {
  final refresh = find.byType(RefreshIndicator).first;
  final listView =
      find.descendant(of: refresh, matching: find.byType(ListView)).first;
  return find.descendant(of: listView, matching: find.byType(Scrollable)).first;
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsAtLeastNWidgets(1));
}

Future<void> _pumpUntilExportRequest(
  WidgetTester tester,
  _ScreenApi api,
  String format,
) async {
  for (var i = 0; i < 30; i++) {
    if (api.requests.any((request) =>
        request.url.path == '/salary/export' &&
        request.url.queryParameters['fmt'] == format)) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('The $format salary export button did not send its request.');
}

Future<void> _tapAdminMore(WidgetTester tester, String title) async {
  await tester.tap(find.byType(NavigationDestination).at(4));
  await tester.pump(const Duration(milliseconds: 450));
  final item = find.widgetWithText(ListTile, title);
  await tester.ensureVisible(item);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(item);
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text(title), findsWidgets);
}

Future<void> _tapCoachMore(
  WidgetTester tester,
  String menuTitle,
  String pageTitle,
) async {
  await tester.tap(find.byType(NavigationDestination).at(4));
  await tester.pump(const Duration(milliseconds: 450));
  final viewportHeight = tester.getSize(find.byType(Scaffold).first).height;
  final sheetHeight = tester.getRect(find.byType(BottomSheet).last).height;
  expect(sheetHeight, lessThan(viewportHeight * 0.55));
  final item = find.widgetWithText(ListTile, menuTitle).last;
  await tester.ensureVisible(item);
  await tester.pump(const Duration(milliseconds: 350));
  expect(item.hitTestable(), findsOneWidget);
  tester.widget<ListTile>(item).onTap!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  expect(find.text(pageTitle), findsOneWidget);
  await tester.pageBack();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _setRole('ADMIN');
  });

  testWidgets('Admin dashboard sections all open on a phone viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ScreenApi()..install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const AdminHome(),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.scrollUntilVisible(
      find.text('Revenue period'),
      250,
      scrollable: _dashboardScrollable(),
    );
    expect(find.text('Revenue period'), findsOneWidget);

    await _tapAdminSection(tester, 1, 'Students');
    await _tapAdminSection(tester, 2, 'Coaches');
    await _tapAdminSection(tester, 3, 'Attendance');
    for (final title in const [
      'Activities',
      'Batches',
      'Reports',
      'Fees',
      'Leave',
      'Settings',
    ]) {
      await _tapAdminMore(tester, title);
    }

    await _tapAdminMore(tester, 'Salary');
    await _pumpUntil(tester, find.text('No salary records yet.'));
    await tester.tap(find.byType(FloatingActionButton).hitTestable());
    await tester.pumpAndSettle();
    final coachPicker = find.byType(DropdownButtonFormField<int>);
    expect(coachPicker, findsOneWidget);
    await tester.tap(coachPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Smoke Test Coach').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '25000');
    final createButton = find.widgetWithText(ElevatedButton, 'Create');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(
      api.requests.any((request) =>
          request.method == 'POST' && request.url.path == '/salary'),
      isTrue,
    );
    expect(find.text('Smoke Test Coach'), findsOneWidget);
    await tester
        .tap(find.byIcon(Icons.notifications_outlined).hitTestable().last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Notifications'), findsOneWidget);

    for (final path in const [
      '/insights/revenue-risk',
      '/dashboard/revenue',
      '/students',
      '/coaches',
      '/attendance/daily-missing',
      '/activities',
      '/batches',
      '/reports',
      '/fees',
      '/salary',
      '/leave/pending',
      '/academy',
      '/notifications',
    ]) {
      expect(api.requests.any((r) => r.url.path == path), isTrue, reason: path);
    }
  });

  testWidgets('Coach dashboard sections all open on a phone viewport',
      (tester) async {
    await _setRole('COACH');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ScreenApi()..install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const CoachHome(),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('My Attendance Today'), findsOneWidget);

    await _tapCoachMore(tester, 'Leave', 'Leave Requests');
    await _tapCoachMore(tester, 'Fees & Receipts', 'Fees & Receipts');
    expect(find.text('Fees from Admin'), findsOneWidget);
    expect(find.textContaining('Assigned Student'), findsOneWidget);
    await _tapCoachMore(tester, 'Fee Reminders', 'Fee Reminders');
    await _tapCoachMore(tester, 'Salary', 'Salary');
    await _tapCoachMore(tester, 'Settings', 'Settings');

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('My Classes'), findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('My Students'), findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Attendance'), findsWidgets);

    await tester.tap(find.byType(NavigationDestination).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester
        .tap(find.byIcon(Icons.notifications_outlined).hitTestable().last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Notifications'), findsOneWidget);

    for (final path in const [
      '/activities/classes/my',
      '/coaches/7/attendance',
      '/coaches/7/activities',
      '/leave/my',
      '/receipts/my',
      '/fees/my',
      '/fee-reminders/my',
      '/salary/coach/7',
      '/auth/me',
      '/notifications',
    ]) {
      expect(api.requests.any((r) => r.url.path == path), isTrue, reason: path);
    }
  });

  testWidgets('Admin salary PDF and CSV buttons request their files',
      (tester) async {
    final row = {
      'id': 1,
      'coach_id': 8,
      'coach_name': 'Smoke Test Coach',
      'month': 11,
      'year': 2026,
      'amount': '25000',
      'notified_at': null,
      'acknowledged_date': null,
    };

    for (final format in const ['pdf', 'csv']) {
      final api = _ScreenApi()..install();
      api.salaryRows.add(row);
      await tester.pumpWidget(MaterialApp(home: const AdminSalaryTab()));
      await _pumpUntil(tester, find.text('Smoke Test Coach'));
      await tester.tap(find.widgetWithText(
          OutlinedButton, format == 'pdf' ? 'Download PDF' : 'Download CSV'));
      await _pumpUntilExportRequest(tester, api, format);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Coach salary PDF and CSV buttons request their files',
      (tester) async {
    await _setRole('COACH');
    for (final format in const ['pdf', 'csv']) {
      final api = _ScreenApi()..install();
      await tester.pumpWidget(MaterialApp(home: const CoachSalaryTab()));
      await _pumpUntil(tester, find.text('November 2026'));
      await tester.tap(find.byTooltip(
          format == 'pdf' ? 'Download salary PDF' : 'Download salary CSV'));
      await _pumpUntilExportRequest(tester, api, format);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
