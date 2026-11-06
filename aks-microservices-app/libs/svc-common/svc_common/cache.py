"""Azure Managed Redis cache-aside helper.

- Entra ID authentication (workload identity) via redis-entraid: tokens are
  refreshed in the background, no password exists.
- Every key is namespaced "<prefix>:<key>" (e.g. app:product-service:...),
  separate from Airflow's Celery keys ("airflow:..."), and every write has a TTL,
  because the shared instance runs with the NoEviction policy.
- Redis failures degrade to cache misses: the database stays the source of truth.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import redis

from .config import CommonSettings

log = logging.getLogger(__name__)
REDIS_ENTRA_SCOPE = "https://redis.azure.com/.default"
MAX_TTL_SECONDS = 24 * 3600


def build_client(settings: CommonSettings) -> redis.Redis:
    if settings.redis_url:
        return redis.Redis.from_url(settings.redis_url, socket_timeout=settings.redis_socket_timeout_seconds)
    kwargs: dict[str, Any] = {
        "host": settings.redis_host,
        "port": settings.redis_port,
        "ssl": settings.redis_ssl,
        "socket_timeout": settings.redis_socket_timeout_seconds,
        "socket_connect_timeout": settings.redis_socket_timeout_seconds,
        "health_check_interval": 30,
        "retry_on_timeout": True,
    }
    if settings.redis_auth_mode == "entra":
        from redis_entraid.cred_provider import create_from_default_azure_credential

        kwargs["credential_provider"] = create_from_default_azure_credential((REDIS_ENTRA_SCOPE,))
    elif settings.redis_auth_mode == "password":
        kwargs["password"] = settings.read_secret_file(settings.redis_password_file)
    return redis.Redis(**kwargs)


class Cache:
    def __init__(self, client: redis.Redis | None, prefix: str) -> None:
        self.client = client
        self.prefix = prefix.rstrip(":")

    def key(self, name: str) -> str:
        return f"{self.prefix}:{name}"

    @property
    def enabled(self) -> bool:
        return self.client is not None

    def get_json(self, name: str) -> Any | None:
        if not self.client:
            return None
        try:
            raw = self.client.get(self.key(name))
        except redis.RedisError as exc:
            log.warning("cache get failed", extra={"key": name, "error": str(exc)})
            return None
        return json.loads(raw) if raw is not None else None

    def set_json(self, name: str, value: Any, ttl_seconds: int) -> None:
        if not self.client:
            return
        if not 0 < ttl_seconds <= MAX_TTL_SECONDS:
            raise ValueError("cache entries must have a TTL (NoEviction policy)")
        try:
            self.client.set(self.key(name), json.dumps(value, default=str), ex=ttl_seconds)
        except redis.RedisError as exc:
            log.warning("cache set failed", extra={"key": name, "error": str(exc)})

    def delete(self, *names: str) -> None:
        if not self.client or not names:
            return
        try:
            self.client.delete(*(self.key(n) for n in names))
        except redis.RedisError as exc:
            log.warning("cache delete failed", extra={"keys": names, "error": str(exc)})

    def incr(self, name: str, ttl_seconds: int = MAX_TTL_SECONDS) -> int | None:
        if not self.client:
            return None
        try:
            pipe = self.client.pipeline()
            pipe.incr(self.key(name))
            pipe.expire(self.key(name), ttl_seconds)
            value, _ = pipe.execute()
            return int(value)
        except redis.RedisError as exc:
            log.warning("cache incr failed", extra={"key": name, "error": str(exc)})
            return None

    def get_int(self, name: str) -> int:
        if not self.client:
            return 0
        try:
            raw = self.client.get(self.key(name))
            return int(raw) if raw is not None else 0
        except redis.RedisError:
            return 0

    def ping(self) -> None:
        if self.client:
            self.client.ping()
