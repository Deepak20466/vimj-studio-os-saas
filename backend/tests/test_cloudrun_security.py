import unittest
from unittest.mock import patch

from app.main import _api_docs_options, app


PUBLIC_API_OPERATIONS = {
    ("GET", "/health"),
    ("POST", "/auth/login"),
    ("POST", "/auth/refresh"),
    ("POST", "/auth/forgot-password"),
    ("POST", "/auth/reset-password"),
}


class CloudRunSecurityTests(unittest.TestCase):
    def test_only_documented_auth_and_health_operations_are_public(self):
        schema = app.openapi()
        unprotected = []
        for path, path_item in schema["paths"].items():
            for method, operation in path_item.items():
                if method.lower() not in {
                    "get", "post", "put", "patch", "delete", "options", "head"
                }:
                    continue
                if (method.upper(), path) in PUBLIC_API_OPERATIONS:
                    continue
                if not operation.get("security"):
                    unprotected.append(f"{method.upper()} {path}")

        self.assertEqual(unprotected, [], f"Public business operations: {unprotected}")

    def test_production_app_hides_interactive_api_documents(self):
        from app.config import settings

        with patch.object(settings, "ENV", "production"):
            self.assertEqual(
                _api_docs_options(settings.ENV),
                {"docs_url": None, "redoc_url": None, "openapi_url": None},
            )


if __name__ == "__main__":
    unittest.main()
