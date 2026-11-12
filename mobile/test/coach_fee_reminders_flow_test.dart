import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';
import 'package:vimj_attendance/core/auth_storage.dart';
import 'package:vimj_attendance/core/app_theme.dart';
import 'package:vimj_attendance/features/coach/coach_fee_reminders_tab.dart';

/// Mirrors the production payloads for a coach (id 86) with one assigned
/// activity and one enrolled student who already has a PAID fee for Nov 2026.
class _FakeBackend {
  final drafts = <Map<String, dynamic>>[];
  final posts = <Map<String, dynamic>>[];
  int postStatus = 201;
  Map<String, dynamic> postError = {};

  void install() {
    ApiClient.instance.setClientForTesting(MockClient(_respond));
  }

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    final headers = {'content-type': 'application/json'};
    if (path == '/fee-reminders/my') {
      return http.Response(jsonEncode(drafts), 200, headers: headers);
    }
    if (path == '/coaches/86/activities') {
      return http.Response(
          jsonEncode([
            {'activity_id': 22, 'activity_name': 'YOGA'}
          ]),
          200,
          headers: headers);
    }
    if (path == '/activities/22/roster') {
      return http.Response(
          jsonEncode([
            {
              'id': 49,
              'name': 'BHUVI DANCE',
              'email': 'bhuvi@example.test',
              'phone': null,
              'phone_secondary': null,
              'enrollment_id': 1,
              'fee_status': 'PAID',
            }
          ]),
          200,
          headers: headers);
    }
    if (path == '/fee-reminders' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      posts.add(body);
      if (postStatus != 201) {
        return http.Response(jsonEncode(postError), postStatus, headers: headers);
      }
      final draft = {
        'id': 7,
        'student_id': body['student_id'],
        'student_name': 'BHUVI DANCE',
        'coach_id': 86,
        'coach_name': 'MEGHA',
        'month': body['month'],
        'year': body['year'],
        'message': body['message'] ?? 'Auto message',
        'status': 'PENDING',
        'decision_note': null,
        'sent_at': null,
        'created_at': '2026-11-12T11:30:00',
        'decided_at': null,
      };
      drafts.insert(0, draft);
      return http.Response(jsonEncode(draft), 201, headers: headers);
    }
    return http.Response(jsonEncode(<dynamic>[]), 200, headers: headers);
  }
}

Future<void> _setCoachSession() async {
  SharedPreferences.setMockInitialValues({});
  await AuthStorage.save(AuthSession(
    userId: 86,
    name: 'MEGHA',
    role: 'COACH',
    accessToken: 'test-token',
    refreshToken: 'test-refresh',
  ));
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: const CoachFeeRemindersTab(),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openFormAndSubmit(WidgetTester tester) async {
  await tester.tap(find.text('New Reminder'));
  await tester.pumpAndSettle();
  expect(find.text('Draft Fee Reminder'), findsOneWidget);
  await tester.tap(find.text('Submit for Approval'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(_setCoachSession);

  testWidgets('a submitted reminder closes the form and appears in the list',
      (tester) async {
    final api = _FakeBackend()..install();
    await _pumpScreen(tester);
    expect(find.text('No fee reminders drafted yet.'), findsOneWidget);

    await _openFormAndSubmit(tester);

    expect(api.posts, hasLength(1));
    expect(api.posts.single['student_id'], 49);
    expect(find.text('Draft Fee Reminder'), findsNothing,
        reason: 'form should close after a successful submit');
    expect(find.textContaining('BHUVI DANCE'), findsWidgets);
    expect(find.text('No fee reminders drafted yet.'), findsNothing);
  });

  testWidgets('a server rejection is shown inside the form', (tester) async {
    final api = _FakeBackend()
      ..postStatus = 400
      ..postError = {'detail': 'No fee record found for this period'}
      ..install();
    await _pumpScreen(tester);

    await _openFormAndSubmit(tester);

    expect(api.posts, hasLength(1));
    expect(find.text('No fee record found for this period'), findsOneWidget);
  });

  testWidgets('Submit is reachable on a phone with a bottom navigation bar',
      (tester) async {
    // Phone-like geometry: 360x800 logical px at 2x, 24px status bar on top,
    // 48px system navigation bar at the bottom.
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 96);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeBackend()..install();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const CoachFeeRemindersTab(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Reminder'));
    await tester.pumpAndSettle();
    final submit = find.text('Submit for Approval');
    final rect = tester.getRect(submit);
    final visibleBottom = 800 - 48.0;
    expect(rect.center.dy, lessThanOrEqualTo(visibleBottom),
        reason: 'Submit button centre is under the navigation bar');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.posts, hasLength(1));
  });
}
