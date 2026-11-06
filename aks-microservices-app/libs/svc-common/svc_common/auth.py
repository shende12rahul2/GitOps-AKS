"""Service-to-service authentication with rotating API keys.

Keys are read from a file mounted by the Key Vault CSI driver (rotated in place
every ~2 minutes when the Key Vault secret changes). Several keys may be valid
at once (one per line or comma separated) so rotation has no downtime:
add the new key, roll callers, remove the old key.
"""

from __future__ import annotations

import hmac
import os
import threading

from fastapi import Header, HTTPException, status

from .config import CommonSettings


class ApiKeyStore:
    def __init__(self, settings: CommonSettings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._mtime: float | None = None
        self._keys: tuple[str, ...] = ()

    def keys(self) -> tuple[str, ...]:
        path = self.settings.internal_api_keys_file
        if path and os.path.exists(path):
            mtime = os.stat(path).st_mtime
            with self._lock:
                if mtime != self._mtime:
                    with open(path, encoding="utf-8") as fh:
                        raw = fh.read()
                    self._keys = _parse(raw)
                    self._mtime = mtime
                return self._keys
        return _parse(self.settings.internal_api_keys or "")

    def primary(self) -> str | None:
        keys = self.keys()
        return keys[0] if keys else None

    def verify(self, presented: str | None) -> bool:
        if not presented:
            return False
        return any(hmac.compare_digest(presented.encode(), k.encode()) for k in self.keys())


def _parse(raw: str) -> tuple[str, ...]:
    return tuple(k.strip() for k in raw.replace(",", "\n").splitlines() if k.strip())


def require_api_key(store: ApiKeyStore):
    def dependency(x_api_key: str | None = Header(default=None)) -> None:
        if not store.verify(x_api_key):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid or missing X-API-Key")

    return dependency
