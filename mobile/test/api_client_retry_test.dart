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
    var attempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      attempts++;
      return http.Response(
        jsonEncode({'access_token': 'token'}),
        attempts == 1 ? 503 : 200,
        headers: const {'content-type': 'application/json'},
      );
    }));

    final result = await ApiClient.instance.post(
      '/auth/login',
      body: const {'email': 'coach@example.test', 'password': 'secret'},
      auth: false,
    );

    expect(attempts, 2);
    expect(result, {'access_token': 'token'});
  });

  test('login retry does not wait for a stalled health warm-up', () async {
    final healthResponse = Completer<http.Response>();
    var loginAttempts = 0;
    ApiClient.instance.setClientForTesting(MockClient((request) async {
      if (request.url.path == '/health') return healthResponse.future;
      loginAttempts++;
      return http.Response(
        jsonEncode({'access_token': 'token'}),
        loginAttempts == 1 ? 503 : 200,
        headers: const {'content-type': 'application/json'},
      );
    }));
    unawaited(ApiClient.instance.warmUp());

    final result = await ApiClient.instance.post(
      '/auth/login',
      body: const {'email': 'coach@example.test', 'password': 'secret'},
      auth: false,
    );

    expect(loginAttempts, 2);
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
}
