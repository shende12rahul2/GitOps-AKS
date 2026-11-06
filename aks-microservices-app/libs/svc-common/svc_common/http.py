"""Outbound HTTP client for service-to-service calls."""

from __future__ import annotations

import httpx

from .auth import ApiKeyStore
from .logging import request_id_var


class ServiceClient:
    def __init__(self, base_url: str, keys: ApiKeyStore, timeout: float = 5.0, transport: httpx.BaseTransport | None = None) -> None:
        self.keys = keys
        self.client = httpx.Client(
            base_url=base_url.rstrip("/"),
            timeout=timeout,
            transport=transport or httpx.HTTPTransport(retries=2),
        )

    def _headers(self, authenticated: bool) -> dict[str, str]:
        headers = {"X-Request-ID": request_id_var.get()}
        if authenticated and (key := self.keys.primary()):
            headers["X-API-Key"] = key
        return headers

    def get(self, path: str, authenticated: bool = False, **kwargs) -> httpx.Response:
        return self.client.get(path, headers=self._headers(authenticated), **kwargs)

    def post(self, path: str, authenticated: bool = True, **kwargs) -> httpx.Response:
        return self.client.post(path, headers=self._headers(authenticated), **kwargs)
