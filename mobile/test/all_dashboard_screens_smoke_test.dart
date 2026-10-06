import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/features/admin/admin_home.dart';
import 'package:vimj_attendance/features/coach/coach_home.dart';

class _ScreenApi {
  final requests = <http.Request>[];

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    Object body = <dynamic>[];

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
    } else if (path == '/notifications') {
      body = {'items': <dynamic>[]};
    }

    return http.Response(
      jsonEncode(body),
      200,
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

    await tester
        .tap(find.byIcon(Icons.notifications_outlined).hitTestable().last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Notifications'), findsOneWidget);

    for (final path in const [
      '/dashboard/summary',
      '/students',
      '/coaches',
      '/attendance/daily-missing',
      '/activities',
      '/batches',
      '/reports',
      '/fees',
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
    await _tapCoachMore(tester, 'Receipts', 'Fee Receipts');
    await _tapCoachMore(tester, 'Fee Reminders', 'Fee Reminders');
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
      '/fee-reminders/my',
      '/auth/me',
      '/notifications',
    ]) {
      expect(api.requests.any((r) => r.url.path == path), isTrue, reason: path);
    }
  });
}
