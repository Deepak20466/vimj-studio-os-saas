"""SMS and WhatsApp notification service (Twilio-backed).

Notifications are best-effort: failures are logged but never raised to the
caller, since a failed reminder should not block an attendance/fee/salary
operation from completing.
"""
import logging

from app.config import settings

logger = logging.getLogger("vimj.notifications")

_client = None


def _get_client():
    global _client
    if not settings.NOTIFICATIONS_ENABLED:
        return None
    if _client is None:
        from twilio.rest import Client

        _client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
    return _client


def send_sms(to_phone: str, message: str) -> bool:
    if not settings.NOTIFICATIONS_ENABLED or not to_phone:
        logger.info("SMS (dry-run) to %s: %s", to_phone, message)
        return False
    try:
        client = _get_client()
        client.messages.create(body=message, from_=settings.TWILIO_SMS_FROM, to=to_phone)
        return True
    except Exception:
        logger.exception("Failed to send SMS to %s", to_phone)
        return False


def send_whatsapp(to_phone: str, message: str) -> bool:
    if not settings.NOTIFICATIONS_ENABLED or not to_phone:
        logger.info("WhatsApp (dry-run) to %s: %s", to_phone, message)
        return False
    try:
        client = _get_client()
        client.messages.create(
            body=message,
            from_=settings.TWILIO_WHATSAPP_FROM,
            to=f"whatsapp:{to_phone}",
        )
        return True
    except Exception:
        logger.exception("Failed to send WhatsApp message to %s", to_phone)
        return False


def notify(to_phone: str, message: str) -> None:
    """Send both SMS and WhatsApp for a notification."""
    send_sms(to_phone, message)
    send_whatsapp(to_phone, message)
