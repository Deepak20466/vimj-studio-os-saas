import unittest
from unittest.mock import patch

from app.services import notifications, scheduler


class NotificationDeliveryTests(unittest.TestCase):
    def test_disabled_external_delivery_does_not_log_phone_or_message(self):
        with (
            patch.object(notifications.settings, "NOTIFICATIONS_ENABLED", False),
            self.assertLogs(notifications.logger, level="INFO") as captured,
        ):
            self.assertFalse(notifications.send_sms("+15551234567", "private reminder text"))
            self.assertFalse(notifications.send_whatsapp("+15551234567", "private reminder text"))

        output = "\n".join(captured.output)
        self.assertNotIn("+15551234567", output)
        self.assertNotIn("private reminder text", output)
        self.assertIn("SMS delivery skipped", output)
        self.assertIn("WhatsApp delivery skipped", output)

    def test_monthly_fee_job_does_not_mark_records_when_delivery_is_disabled(self):
        with (
            patch.object(scheduler.settings, "NOTIFICATIONS_ENABLED", False),
            patch.object(scheduler, "SessionLocal") as session_local,
            self.assertLogs(scheduler.logger, level="INFO") as captured,
        ):
            scheduler.job_monthly_fee_reminders()

        session_local.assert_not_called()
        self.assertIn("Monthly fee reminders skipped", "\n".join(captured.output))


if __name__ == "__main__":
    unittest.main()
