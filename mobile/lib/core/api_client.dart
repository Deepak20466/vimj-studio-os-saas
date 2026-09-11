import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final http.Client _http = http.Client();
  // Shared by every concurrent caller that hits a 401 at the same time (e.g. a screen
  // that fires several parallel GETs via Future.wait right as the access token expires).
  // Without sharing this future, only the first caller would actually refresh — every
  // other concurrent caller used to see a refresh "already in progress" and immediately
  // treat that as a failed refresh, clearing the session and logging the user out even
  // though the real refresh was about to succeed a moment later. That race was the actual
  // cause of "gets logged out on its own" during normal use, not the token lifetime itself.
  Future<bool>? _refreshFuture;

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
      queryParameters: cleanQuery != null && cleanQuery.isNotEmpty ? cleanQuery : null,
    );
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
    return _refreshFuture ??= _performRefresh().whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _performRefresh() async {
    try {
      final session = await AuthStorage.load();
      if (session == null) return false;
      final response = await _http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': session.refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = await _decode(response) as Map<String, dynamic>;
      await AuthStorage.updateAccessToken(
        data['access_token'] as String,
        refreshToken: data['refresh_token'] as String?,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool auth = true,
    bool isRetry = false,
  }) async {
    final uri = _uri(path, query);
    final headers = await _headers(auth: auth);
    final encodedBody = body != null ? jsonEncode(body) : null;

    http.Response response;
    switch (method) {
      case 'GET':
        response = await _http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _http.post(uri, headers: headers, body: encodedBody);
        break;
      case 'PUT':
        response = await _http.put(uri, headers: headers, body: encodedBody);
        break;
      case 'DELETE':
        response = await _http.delete(uri, headers: headers);
        break;
      default:
        throw ApiException(0, 'Unsupported method $method');
    }

    if (response.statusCode == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _request(method, path, query: query, body: body, auth: auth, isRetry: true);
      }
      await AuthStorage.clear();
      throw ApiException(401, 'Session expired. Please log in again.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }

    String message = 'Request failed (${response.statusCode})';
    try {
      final data = await _decode(response);
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        message = detail is String ? detail : jsonEncode(detail);
      }
    } catch (_) {
      // keep default message
    }
    throw ApiException(response.statusCode, message);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query, bool auth = true}) =>
      _request('GET', path, query: query, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _request('POST', path, body: body, auth: auth);

  Future<dynamic> put(String path, {Object? body, Map<String, dynamic>? query, bool auth = true}) =>
      _request('PUT', path, query: query, body: body, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) => _request('DELETE', path, auth: auth);

  /// For endpoints that return a raw file (CSV/PDF export, receipt PDF) rather than JSON.
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    final uri = _uri(path, query);
    final headers = await _headers();
    final response = await _http.get(uri, headers: headers);
    if (response.statusCode == 401) {
      final refreshed = await _tryRefresh();
      if (refreshed) return getBytes(path, query: query);
      await AuthStorage.clear();
      throw ApiException(401, 'Session expired. Please log in again.');
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
      throw ApiException(response.statusCode, message);
    }
    return response.bodyBytes;
  }
}
