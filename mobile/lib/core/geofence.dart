import 'dart:math';

/// Mirrors the backend's Haversine geofence check (app/services/geofence.py)
/// so the app can warn the user before it even attempts to submit.
class Geofence {
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLambda = (lng2 - lng1) * pi / 180;

    final a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static bool isWithin(double lat, double lng, double facilityLat, double facilityLng, {double radiusMeters = 100}) {
    return distanceMeters(lat, lng, facilityLat, facilityLng) <= radiusMeters;
  }
}
