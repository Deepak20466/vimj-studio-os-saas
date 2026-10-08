import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_storage.dart';

const _requestTimeout = Duration(seconds: 25);
const _loginTimeout = Duration(seconds: 75);
const _loginAttemptTimeout = Duration(seconds: 25);
const _loginRetryWarmUpWait = Duration(seconds: 2);
const _loginTimeoutMessage =
    'The server is taking too long to wake up. Please try signing in again in a moment.';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Duration? retryAfter;
  ApiException(this.statusCode, this.message, {this.retryAfter});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  http.Client _http = http.Client();
  Future<void>? _warmUpFuture;
  DateTime? _lastWarmUpCompletedAt;
  // Shared by every concurrent caller that hits a 401 at the same time (e.g. a screen
  // that fires several parallel GETs via Future.wait right as the access token expires).
  // Without sharing this future, only the first caller would actually refresh — every
  // other concurrent caller used to see a refresh "already in progress" and immediately
  // treat that as a failed refresh, clearing the session and logging the user out even
  // though the real refresh was about to succeed a moment later. That race was the actual
  // cause of "gets logged out on its own" during normal use, not the token lifetime itself.
  Future<bool>? _refreshFuture;

  @visibleForTesting
  void setClientForTesting(http.Client client) {
    _http.close();
    _http = client;
    _refreshFuture = null;
    _warmUpFuture = null;
    _lastWarmUpCompletedAt = null;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    Map<String, String>? cleanQuery;
    if (query != null) {
      cleanQuery = <String, String>{};
      for (final entry in query.entries) {
        if (entry.value != null) {
          cleanQuery[entry.key] = entry.value.toString();
        }
      }
    }
    return Uri.parse('${ApiConfig.baseUrl}$path').replace(
      queryParameters:
          cleanQuery != null && cleanQuery.isNotEmpty ? cleanQuery : null,
    );
  }

  /// Best-effort, non-authenticated ping used by the login screen to wake the
  /// production host while the user is entering credentials.
  Future<void> warmUp() {
    final pending = _warmUpFuture;
    if (pending != null) return pending;
    final lastCompletedAt = _lastWarmUpCompletedAt;
    if (lastCompletedAt != null &&
        DateTime.now().difference(lastCompletedAt) <
            const Duration(minutes: 5)) {
      return Future.value();
    }

    late final Future<void> tracked;
    tracked = _performWarmUp().then((succeeded) {
      // Only suppress another ping when the health endpoint actually responded.
      // A failed probe should be retried on the next login attempt.
      if (succeeded) _lastWarmUpCompletedAt = DateTime.now();
    }).whenComplete(() {
      if (identical(_warmUpFuture, tracked)) _warmUpFuture = null;
    });
    _warmUpFuture = tracked;
    return tracked;
  }

  Future<bool> _performWarmUp() async {
    try {
      final response = await _http.get(_uri('/health')).timeout(_loginTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // A warm-up failure must not affect the actual login attempt.
      return false;
    }
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final session = await AuthStorage.load();
      if (session != null) {
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    return headers;
  }

  Future<dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return Future.value(null);
    return Future.value(jsonDecode(response.body));
  }

  Future<bool> _tryRefresh() {
    // If a refresh is already in flight, piggyback on it instead of racing a second
    // one — see the comment on _refreshFuture above.
    return _refreshFuture ??=
        _performRefresh().whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _performRefresh() async {
    final session = await AuthStorage.load();
    if (session == null) return false;

    final response = await _sendRefresh(session);
    if (response.statusCode == 401) return false;
    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _responseMessage(
          response,
          fallback: 'Could not renew your session. Please try again shortly.',
          unavailable:
              'The server is temporarily unavailable. Your saved session is safe; please try again shortly.',
          login: false,
        ),
        retryAfter: _retryAfter(response),
      );
    }

    final dynamic decoded;
    try {
      decoded = await _decode(response);
    } catch (_) {
      throw ApiException(
        0,
        'The server returned an invalid session response. Your saved session is safe; please try again.',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['access_token'] is! String) {
      throw ApiException(
        0,
        'The server returned an invalid session response. Your saved session is safe; please try again.',
      );
    }

    await AuthStorage.updateAccessToken(
      decoded['access_token'] as String,
      refreshToken: decoded['refresh_token'] as String?,
    );
    return true;
  }

  Future<http.Response> _sendRefresh(AuthSession session,
      {bool retriedTransient = false}) async {
    late final http.Response response;
    try {
      response = await _http
          .post(
            _uri('/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': session.refreshToken}),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      if (!retriedTransient) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _sendRefresh(session, retriedTransient: true);
      }
      throw ApiException(
        0,
        'The server did not respond while renewing your session. Your saved session is safe; please try again shortly.',
      );
    } on http.ClientException {
      if (!retriedTransient) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _sendRefresh(session, retriedTransient: true);
      }
      throw ApiException(
        0,
        'Could not connect while renewing your session. Your saved session is safe; check your connection and try again.',
      );
    }

    final transientServerError =
        response.statusCode >= 500 && response.statusCode < 600;
    if (!retriedTransient && transientServerError) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return _sendRefresh(session, retriedTransient: true);
    }
    return response;
  }

  Future<void> _refreshOrThrowSessionExpired() async {
    if (await _tryRefresh()) return;
    await AuthStorage.clear();
    throw ApiException(401, 'Session expired. Please log in again.');
  }

  Duration? _retryAfter(http.Response response) {
    final value = response.headers['retry-after']?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return Duration(seconds: seconds > 0 ? seconds : 1);
    }
    final retryAt = DateTime.tryParse(value);
    if (retryAt == null) return null;
    final remaining = retryAt.toUtc().difference(DateTime.now().toUtc());
    return remaining > Duration.zero ? remaining : const Duration(seconds: 1);
  }

  String _responseMessage(
    http.Response response, {
    required String fallback,
    required String unavailable,
    required bool login,
  }) {
    if (response.statusCode == 429) {
      final delay = _retryAfter(response);
      final wait = delay == null ? null : _describeDelay(delay);
      if (login) {
        return wait == null
            ? 'Too many sign-in attempts. Please wait before trying again.'
            : 'Too many sign-in attempts. Please wait $wait before trying again.';
      }
      return wait == null
          ? 'Too many requests. Please wait before trying again.'
          : 'Too many requests. Please wait $wait before trying again.';
    }

    var message = fallback;
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final detail = data['detail'] ?? data['error'] ?? data['message'];
        if (detail != null) {
          message = detail is String ? detail : jsonEncode(detail);
        }
      }
    } catch (_) {
      // Keep the fallback when the gateway body is not JSON.
    }
    if (response.statusCode >= 500 &&
        response.statusCode < 600 &&
        message == fallback) {
      return unavailable;
    }
    return message;
  }

  String _describeDelay(Duration delay) {
    final seconds = delay.inSeconds.ceil();
    if (seconds < 60) {
      return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    }
    final minutes = (seconds + 59) ~/ 60;
    if (minutes < 60) {
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    }
    final hours = (minutes + 59) ~/ 60;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool auth = true,
    bool isRetry = false,
    bool retriedTransient = false,
    Stopwatch? loginTimer,
  }) async {
    final requestLoginTimer =
        loginTimer ?? (path == '/auth/login' ? (Stopwatch()..start()) : null);
    final uri = _uri(path, query);
    final headers = await _headers(auth: auth);
    final encodedBody = body != null ? jsonEncode(body) : null;
    final timeout = path == '/auth/login'
        ? _loginAttemptBudget(requestLoginTimer)
        : _requestTimeout;

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response =
              await _http.get(uri, headers: headers).timeout(_requestTimeout);
          break;
        case 'POST':
          response = await _http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(timeout);
          break;
        case 'PUT':
          response = await _http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout);
          break;
        case 'DELETE':
          response = await _http
              .delete(uri, headers: headers)
              .timeout(_requestTimeout);
          break;
        default:
          throw ApiException(0, 'Unsupported method $method');
      }
    } on TimeoutException {
      if (path == '/auth/login') {
        if (!retriedTransient) {
          await _waitForLoginRetry(requestLoginTimer);
          return _request(method, path,
              query: query,
              body: body,
              auth: auth,
              isRetry: isRetry,
              retriedTransient: true,
              loginTimer: requestLoginTimer);
        }
        throw ApiException(0, _loginTimeoutMessage);
      }
      throw ApiException(0,
          'The server did not respond in time. Check your connection and try again.');
    } on http.ClientException {
      if (!retriedTransient && (method == 'GET' || path == '/auth/login')) {
        if (path == '/auth/login') {
          await _waitForLoginRetry(requestLoginTimer);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        return _request(method, path,
            query: query,
            body: body,
            auth: auth,
            isRetry: isRetry,
            retriedTransient: true,
            loginTimer: requestLoginTimer);
      }
      throw ApiException(0,
          'Could not connect to the server. Check your connection and try again.');
    }

    // Retry safe reads and login once after transient server errors so a brief
    // backend or gateway failure does not immediately surface to the user.
    final transientServerError =
        response.statusCode >= 500 && response.statusCode < 600;
    if (!retriedTransient &&
        (method == 'GET' || path == '/auth/login') &&
        transientServerError) {
      if (path == '/auth/login') {
        await _waitForLoginRetry(requestLoginTimer);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      return _request(method, path,
          query: query,
          body: body,
          auth: auth,
          isRetry: isRetry,
          retriedTransient: true,
          loginTimer: requestLoginTimer);
    }

    if (response.statusCode == 401 && auth && !isRetry) {
      await _refreshOrThrowSessionExpired();
      return _request(method, path,
          query: query,
          body: body,
          auth: auth,
          isRetry: true,
          retriedTransient: retriedTransient);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }

    final message = _responseMessage(
      response,
      fallback: 'Request failed (${response.statusCode})',
      unavailable: path == '/auth/login'
          ? 'The server is temporarily unavailable. Please try signing in again shortly.'
          : 'The server is temporarily unavailable. Please try again shortly.',
      login: path == '/auth/login',
    );
    throw ApiException(response.statusCode, message,
        retryAfter: _retryAfter(response));
  }

  Duration _remainingLoginTimeout(Stopwatch? timer) {
    final remaining = _loginTimeout - (timer?.elapsed ?? Duration.zero);
    if (remaining <= Duration.zero) {
      throw ApiException(0, _loginTimeoutMessage);
    }
    return remaining;
  }

  Duration _loginAttemptBudget(Stopwatch? timer) {
    final remaining = _remainingLoginTimeout(timer);
    return remaining < _loginAttemptTimeout ? remaining : _loginAttemptTimeout;
  }

  Future<void> _waitForLoginRetry(Stopwatch? timer) async {
    final remaining = _remainingLoginTimeout(timer);
    final pendingWarmUp = _warmUpFuture;
    if (pendingWarmUp != null) {
      // Let the health request make progress, but don't make a failed login wait
      // for the entire cold-start window before its retry. The login request
      // itself retains the remaining part of the 75-second overall budget.
      final wait =
          remaining < _loginRetryWarmUpWait ? remaining : _loginRetryWarmUpWait;
      try {
        await pendingWarmUp.timeout(wait);
      } on TimeoutException {
        _remainingLoginTimeout(timer);
      }
      return;
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400))
          .timeout(remaining);
    } on TimeoutException {
      _remainingLoginTimeout(timer);
    }
  }

  Future<dynamic> get(String path,
          {Map<String, dynamic>? query, bool auth = true}) =>
      _request('GET', path, query: query, auth: auth);

  /// Reads every row from a paginated list endpoint. The API caps each
  /// response at 1,000 rows to keep individual responses manageable.
  Future<List<dynamic>> getAllPages(String path,
      {Map<String, dynamic>? query,
      int pageSize = 1000,
      String? itemsKey}) async {
    if (pageSize < 1 || pageSize > 1000) {
      throw ArgumentError.value(
          pageSize, 'pageSize', 'must be between 1 and 1,000');
    }

    final rows = <dynamic>[];
    var offset = 0;
    String? previousPageSignature;
    while (true) {
      final response = await get(path, query: {
        ...?query,
        'limit': pageSize,
        'offset': offset,
      });
      final page = itemsKey == null
          ? response
          : response is Map<String, dynamic>
              ? response[itemsKey]
              : null;
      if (page is! List) {
        throw ApiException(0, 'The server returned an invalid list response.');
      }
      final pageSignature = jsonEncode(page);
      if (offset > 0 && pageSignature == previousPageSignature) {
        throw ApiException(
            0, 'List paging is unavailable. Please try again shortly.');
      }
      previousPageSignature = pageSignature;
      rows.addAll(page);
      if (page.length < pageSize) return rows;
      offset += page.length;
    }
  }

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _request('POST', path, body: body, auth: auth);

  Future<dynamic> put(String path,
          {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _request('PUT', path, query: query, body: body, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) =>
      _request('DELETE', path, auth: auth);

  /// For endpoints that return a raw file (CSV/PDF export, receipt PDF) rather than JSON.
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) =>
      _getBytes(path, query: query);

  Future<List<int>> _getBytes(String path,
      {Map<String, dynamic>? query, bool retriedTransient = false}) async {
    final uri = _uri(path, query);
    final headers = await _headers();
    late final http.Response response;
    try {
      response =
          await _http.get(uri, headers: headers).timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(0,
          'The server did not respond in time. Check your connection and try again.');
    } on http.ClientException {
      if (!retriedTransient) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _getBytes(path, query: query, retriedTransient: true);
      }
      throw ApiException(0,
          'Could not connect to the server. Check your connection and try again.');
    }
    if (!retriedTransient &&
        response.statusCode >= 500 &&
        response.statusCode < 600) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return _getBytes(path, query: query, retriedTransient: true);
    }
    if (response.statusCode == 401) {
      await _refreshOrThrowSessionExpired();
      return _getBytes(path, query: query, retriedTransient: retriedTransient);
    }
    if (response.statusCode == 429) {
      final retryAfter = _retryAfter(response);
      throw ApiException(
        429,
        _responseMessage(
          response,
          fallback: 'Download failed (429)',
          unavailable: 'The server is temporarily unavailable.',
          login: false,
        ),
        retryAfter: retryAfter,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Download failed (${response.statusCode})';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] != null) {
          final detail = data['detail'];
          message = detail is String ? detail : jsonEncode(detail);
        }
      } catch (_) {
        // keep default message — body wasn't JSON
      }
      if (response.statusCode >= 500 &&
          response.statusCode < 600 &&
          message == 'Download failed (${response.statusCode})') {
        message =
            'The server is temporarily unavailable. Please try again shortly.';
      }
      throw ApiException(response.statusCode, message);
    }
    return response.bodyBytes;
  }
}
