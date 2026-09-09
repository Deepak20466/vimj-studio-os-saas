import 'package:flutter/foundation.dart' show kIsWeb;

/// Backend base URL.
///
/// - Web (Chrome): http://localhost:8000
/// - Android emulator reaching a backend on the host machine: http://10.0.2.2:8000
/// - iOS simulator: http://localhost:8000
/// - Physical device: http://<your-lan-ip>:8000
/// - Production: https://api.your-domain.example.com
///
/// Override at build time with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');
  // kIsWeb can't be reached from a browser, so it always needs localhost,
  // regardless of the Android-emulator-oriented compiled-in default below.
  static final String baseUrl = _override.isNotEmpty
      ? _override
      : (kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000');
}

/// Client-side mirror of the backend's facility geofence settings, used only
/// to give the coach instant feedback before submitting — the server is the
/// source of truth and re-validates every request independently.
class FacilityConfig {
  // Defaults are VIMJ Studio's real facility (geocoded from its address — see
  // backend/app/config.py for the full note); still override via --dart-define if a more
  // exact pin becomes available.
  static final double lat = double.parse(const String.fromEnvironment('FACILITY_LAT', defaultValue: '12.9745723'));
  static final double lng = double.parse(const String.fromEnvironment('FACILITY_LNG', defaultValue: '77.5689324'));
  static final double radiusMeters =
      double.parse(const String.fromEnvironment('GEOFENCE_RADIUS_METERS', defaultValue: '100'));
}
