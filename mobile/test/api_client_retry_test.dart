import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vimj_attendance/core/api_client.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.instance.setClientForTesting(http.Client());
  });

  test('safe JSON GET retries a transient server error once', () async {
    var attempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      attempts++;
      return http.Response(
        jsonEncode({'ok': true}),
        attempts == 1 ? 500 : 200,
        headers: const {'content-type': 'application/json'},
      );
    }));

    final result = await ApiClient.instance.get('/health', auth: false);

    expect(attempts, 2);
    expect(result, {'ok': true});
  });

  test('login retries a transient server error once', () async {
    var loginAttempts = 0;
    var healthAttempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      if (request.url.path == '/health') {
        healthAttempts++;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }
      loginAttempts++;
      return http.Response(
        jsonEncode({'access_token': 'token'}),
        loginAttempts == 1 ? 503 : 200,
        headers: const {'content-type': 'application/json'},
      );
    }));

    final result = await ApiClient.instance.post(
      '/auth/login',
      body: const {'email': 'coach@example.test', 'password': 'secret'},
      auth: false,
    );

    expect(healthAttempts, 2);
    expect(loginAttempts, 2);
    expect(result, {'access_token': 'token'});
  });

  test('login retries a transient request timeout once', () async {
    var loginAttempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }
      loginAttempts++;
      if (loginAttempts == 1) throw TimeoutException('temporary timeout');
      return http.Response(
        jsonEncode({'access_token': 'token'}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }));

    final result = await ApiClient.instance.post(
      '/auth/login',
      body: const {'email': 'coach@example.test', 'password': 'secret'},
      auth: false,
    );

    expect(loginAttempts, 2);
    expect(result, {'access_token': 'token'});
  });

  test('login waits for health readiness instead of retrying sign-in on 503',
      () async {
    var healthAttempts = 0;
    var loginAttempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      if (request.url.path == '/health') {
        healthAttempts++;
        return http.Response(
          jsonEncode({'status': healthAttempts > 1 ? 'ok' : 'starting'}),
          healthAttempts > 1 ? 200 : 503,
        );
      }
      loginAttempts++;
      return http.Response(jsonEncode({'access_token': 'token'}), 200,
          headers: const {'content-type': 'application/json'});
    }));

    final result = await ApiClient.instance.post(
      '/auth/login',
      body: const {'email': 'coach@example.test', 'password': 'secret'},
      auth: false,
    );

    expect(healthAttempts, 2);
    expect(loginAttempts, 1);
    expect(result, {'access_token': 'token'});
  });

  test('raw PDF GET retries a transient server error once', () async {
    var attempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      attempts++;
      return http.Response(
        attempts == 1 ? 'temporary failure' : '%PDF-1.7',
        attempts == 1 ? 502 : 200,
      );
    }));

    final result = await ApiClient.instance.getBytes('/reports/export');

    expect(attempts, 2);
    expect(utf8.decode(result), '%PDF-1.7');
  });

  test('safe JSON GET retries one connection failure', () async {
    var attempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      attempts++;
      if (attempts == 1) throw http.ClientException('temporary network error');
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }));

    final result = await ApiClient.instance.get('/health', auth: false);

    expect(attempts, 2);
    expect(result, {'ok': true});
  });

  test('attendance GET loads successive pages and preserves filters', () async {
    final offsets = <int>[];
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      offsets.add(int.parse(request.url.queryParameters['offset']!));
      expect(request.url.queryParameters['limit'], '2');
      expect(request.url.queryParameters['date_from'], '2026-09-01');
      final page = offsets.length == 1
          ? [
              {'id': 1},
              {'id': 2},
            ]
          : [
              {'id': 3},
            ];
      return http.Response(jsonEncode(page), 200);
    }));

    final result = await ApiClient.instance.getAllPages(
      '/attendance/students',
      pageSize: 2,
      query: const {'date_from': '2026-09-01'},
    );

    expect(offsets, [0, 2]);
    expect(result, [
      {'id': 1},
      {'id': 2},
      {'id': 3},
    ]);
  });

  test('attendance GET stops if server repeats a page', () async {
    var attempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      attempts++;
      return http.Response(
          jsonEncode([
            {'id': 1},
            {'id': 2}
          ]),
          200);
    }));

    await expectLater(
      ApiClient.instance.getAllPages('/attendance/students', pageSize: 2),
      throwsA(isA<ApiException>()),
    );
    expect(attempts, 2);
  });
}
