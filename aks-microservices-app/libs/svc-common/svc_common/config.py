"""Twelve-factor configuration. Every value comes from the environment (ConfigMap,
downward API, workload identity webhook). Secrets are never environment
variables: they are files mounted by the Key Vault CSI driver."""

from __future__ import annotations

from functools import cached_property
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class CommonSettings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore", case_sensitive=False)

    service_name: str = "service"
    environment: str = "local"
    log_level: str = "INFO"
    version: str = Field(default="dev", alias="APP_VERSION")

    # Downward API (pod/node identity, used to prove cross-node behaviour).
    pod_name: str = Field(default="local", alias="POD_NAME")
    node_name: str = Field(default="local", alias="NODE_NAME")

    # --- PostgreSQL -----------------------------------------------------------
    db_enabled: bool = True
    database_url: str | None = None  # full override (tests: sqlite)
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "postgres"
    db_user: str = "postgres"
    db_auth_mode: Literal["entra", "password"] = "password"
    db_password_file: str | None = None
    db_password: str | None = None  # local development only
    db_sslmode: str = "require"
    db_schema: str | None = None  # None = public; else search_path for every connection
    db_pool_size: int = 3
    db_max_overflow: int = 2
    db_pool_recycle_seconds: int = 1800
    db_connect_timeout_seconds: int = 10

    # --- Redis (Azure Managed Redis) -------------------------------------------
    redis_enabled: bool = False
    redis_url: str | None = None  # override (tests/local: redis://localhost:6379/0)
    redis_host: str = "localhost"
    redis_port: int = 10000
    redis_ssl: bool = True
    redis_auth_mode: Literal["entra", "password", "none"] = "entra"
    redis_password_file: str | None = None
    redis_key_prefix: str = "app"
    redis_socket_timeout_seconds: float = 2.0

    # --- Service-to-service API keys --------------------------------------------
    internal_api_keys_file: str | None = "/mnt/secrets/internal-api-key"
    internal_api_keys: str | None = None  # local development only (comma separated)

    # --- Azure Files shared volume ------------------------------------------------
    shared_storage_enabled: bool = False
    shared_mount_path: str = "/mnt/shared"

    # --- HTTP -----------------------------------------------------------------
    hsts_enabled: bool = True
    cors_allow_origins: str = ""

    @cached_property
    def api_prefix(self) -> str:
        """Every backend serves its routes under /api/<resource>."""
        return "/api/" + self.service_name.removesuffix("-service") + "s"

    def read_secret_file(self, path: str | None) -> str | None:
        if not path:
            return None
        p = Path(path)
        return p.read_text(encoding="utf-8").strip() if p.exists() else None
