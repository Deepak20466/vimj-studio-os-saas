from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    DATABASE_URL: str = "postgresql+psycopg2://vimj_user:changeme@localhost:5432/vimj_attendance"

    JWT_SECRET_KEY: str = "dev-secret-change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    # Rotated on every /auth/refresh call (see routers/auth.py), so this is really a
    # sliding "must open the app at least this often" window, not a hard session cap.
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    FRONTEND_ORIGIN: str = "http://localhost:5173"
    # Expo's web dev server (`expo start --web`) picks 8081/8082/8083 depending
    # on what's free, so the mobile app in a browser needs its own allowed origin.
    MOBILE_WEB_ORIGIN: str = "http://localhost:8082"

    # VIMJ Studio's real facility (near Chowdeswari Temple, TD Ln, Subhash Nagar, Cottonpete,
    # Bengaluru 560053) — geocoded from the address on 2026-09-09; this was previously left at
    # a placeholder ~3km away (central Bangalore demo coordinates), which meant every real
    # attendance-marking attempt at the actual facility failed the geofence check unconditionally,
    # with no way to tell from the error alone that the *coordinates*, not the coach's location,
    # were the problem. Address-level geocoding is only accurate to roughly a city block — get
    # the exact pin (stand at the facility, long-press the spot in Google Maps, share the
    # coordinates shown) and update this if attendance marking still fails near the real building.
    FACILITY_LAT: float = 12.9745723
    FACILITY_LNG: float = 77.5689324
    # 50m assumes near-perfect GPS; consumer phones commonly drift 20-50m indoors/near
    # buildings even with correct facility coordinates, which reads identically to a real
    # coordinate misconfiguration ("nothing happens" with no indication why). 100m keeps
    # geofencing meaningful while tolerating that drift.
    GEOFENCE_RADIUS_METERS: float = 100

    UPLOAD_DIR: str = "uploads/selfies"
    STUDENT_PHOTO_DIR: str = "uploads/students"
    CLASS_PHOTO_DIR: str = "uploads/class_photos"
    MAX_SELFIE_SIZE_KB: int = 500

    TWILIO_ACCOUNT_SID: str = ""
    TWILIO_AUTH_TOKEN: str = ""
    TWILIO_SMS_FROM: str = ""
    TWILIO_WHATSAPP_FROM: str = "whatsapp:+14155238886"
    NOTIFICATIONS_ENABLED: bool = False

    LOGIN_RATE_LIMIT: str = "5/15minutes"

    ENV: str = "development"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
