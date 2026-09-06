"""SMS and WhatsApp notification service (Twilio-backed).

Notifications are best-effort: failures are logged but never raised to the
caller, since a failed reminder should not block an attendance/fee/salary
operation from completing.
"""
import calendar
import logging
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy.orm import Session

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


def push_inapp(
    db: Session,
    user_id: int,
    type: str,
    title: str,
    message: str,
    link: Optional[str] = None,
    delay_minutes: Optional[int] = None,
) -> None:
    """Write a bell-notification row for a user. Caller is responsible for committing."""
    from app.models.notification import Notification

    db.add(
        Notification(
            user_id=user_id,
            type=type,
            title=title,
            message=message,
            link=link,
            delay_minutes=delay_minutes,
        )
    )


def notify_and_push(
    db: Session,
    user,
    message: str,
    title: str,
    type: str,
    link: Optional[str] = None,
    delay_minutes: Optional[int] = None,
) -> None:
    """Send SMS/WhatsApp (if the user has a phone) and write a bell notification. Caller commits."""
    if user and getattr(user, "phone", None):
        notify(user.phone, message)
    if user:
        push_inapp(db, user.id, type, title, message, link=link, delay_minutes=delay_minutes)


def fee_reminder_message(student_name: str, month: int, year: int, amount: Decimal, due_date: Optional[date]) -> str:
    """The standard fee-reminder WhatsApp/SMS wording, shared by the scheduled job, the manual
    admin "Remind" action, and the default text a coach's fee-reminder draft starts from."""
    month_name = calendar.month_name[month]
    due_str = due_date.strftime("%d/%m/%Y") if due_date else "the due date"
    return (
        f"Dear {student_name},\n"
        f"This is a reminder of your pending fee balance for the month of {month_name} of Rs {amount}. "
        f"Kindly pay before end of {due_str}. Ignore if paid."
    )
