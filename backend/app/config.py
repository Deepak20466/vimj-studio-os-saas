from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    DATABASE_URL: str = "postgresql+psycopg2://vimj_user:changeme@localhost:5432/vimj_attendance"

    JWT_SECRET_KEY: str = "dev-secret-change-me"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    FRONTEND_ORIGIN: str = "http://localhost:5173"
    # Expo's web dev server (`expo start --web`) picks 8081/8082/8083 depending
    # on what's free, so the mobile app in a browser needs its own allowed origin.
    MOBILE_WEB_ORIGIN: str = "http://localhost:8082"

    FACILITY_LAT: float = 12.9716
    FACILITY_LNG: float = 77.5946
    GEOFENCE_RADIUS_METERS: float = 50

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
