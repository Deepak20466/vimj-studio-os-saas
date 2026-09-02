/// Backend base URL.
///
/// - Android emulator reaching a backend on the host machine: http://10.0.2.2:8000
/// - iOS simulator: http://localhost:8000
/// - Physical device: http://<your-lan-ip>:8000
/// - Production: https://api.your-domain.example.com
///
/// Override at build time with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}

/// Client-side mirror of the backend's facility geofence settings, used only
/// to give the coach instant feedback before submitting — the server is the
/// source of truth and re-validates every request independently.
class FacilityConfig {
  static const double lat = double.fromEnvironment('FACILITY_LAT', defaultValue: 12.9716);
  static const double lng = double.fromEnvironment('FACILITY_LNG', defaultValue: 77.5946);
  static const double radiusMeters = double.fromEnvironment('GEOFENCE_RADIUS_METERS', defaultValue: 50);
}
