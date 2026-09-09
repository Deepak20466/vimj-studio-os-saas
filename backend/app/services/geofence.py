import math

from app.config import settings


def haversine_distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two lat/lng points, in meters."""
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def geofence_check(lat: float, lng: float, radius_meters: float = None) -> tuple[bool, float, float]:
    """Like is_within_geofence, but also returns (distance, radius) so callers can put the
    actual numbers in the rejection message — otherwise a facility-coordinate misconfiguration
    (wrong lat/lng shipped in an app build vs. what the backend has) looks identical to "the
    button doesn't work" with no way to tell the two apart from the error alone."""
    radius = radius_meters if radius_meters is not None else settings.GEOFENCE_RADIUS_METERS
    distance = haversine_distance_meters(lat, lng, settings.FACILITY_LAT, settings.FACILITY_LNG)
    return distance <= radius, distance, radius
