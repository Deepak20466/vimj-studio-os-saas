"""Compatibility import for the versioned insights router."""

from app.api.v1.insights import router, versioned_router

__all__ = ["router", "versioned_router"]
