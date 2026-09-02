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


def is_within_geofence(lat: float, lng: float, radius_meters: float = None) -> bool:
    radius = radius_meters if radius_meters is not None else settings.GEOFENCE_RADIUS_METERS
    distance = haversine_distance_meters(lat, lng, settings.FACILITY_LAT, settings.FACILITY_LNG)
    return distance <= radius
