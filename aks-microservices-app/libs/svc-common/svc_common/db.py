"""SQLAlchemy engine with passwordless Microsoft Entra ID authentication.

In AKS the workload identity webhook injects AZURE_CLIENT_ID, AZURE_TENANT_ID and
AZURE_FEDERATED_TOKEN_FILE. DefaultAzureCredential exchanges the projected
service-account token for an Entra access token, which PostgreSQL accepts as
the password of the role named after the managed identity. A fresh token is
fetched for every *new* physical connection; pooled connections stay valid
after the token expires, so `pool_recycle` only bounds connection age.
"""

from __future__ import annotations

import logging
from collections.abc import Iterator
from urllib.parse import quote_plus

from sqlalchemy import Engine, create_engine, event, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from .config import CommonSettings

log = logging.getLogger(__name__)

PG_ENTRA_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self, settings: CommonSettings) -> None:
        self.settings = settings
        self.engine = self._create_engine()
        self.session_factory = sessionmaker(bind=self.engine, expire_on_commit=False)

    def _url(self) -> str:
        s = self.settings
        if s.database_url:
            return s.database_url
        return f"postgresql+psycopg://{quote_plus(s.db_user)}@{s.db_host}:{s.db_port}/{s.db_name}"

    def _create_engine(self) -> Engine:
        s = self.settings
        url = self._url()
        if url.startswith("sqlite"):
            # Unit tests: one shared in-memory database across threads.
            return create_engine(url, connect_args={"check_same_thread": False}, poolclass=StaticPool)

        engine = create_engine(
            url,
            pool_size=s.db_pool_size,
            max_overflow=s.db_max_overflow,
            pool_recycle=s.db_pool_recycle_seconds,
            pool_pre_ping=True,
            connect_args={
                "sslmode": s.db_sslmode,
                "connect_timeout": s.db_connect_timeout_seconds,
                "application_name": s.service_name,
                **({"options": f"-csearch_path={s.db_schema}"} if s.db_schema else {}),
            },
        )

        if s.db_auth_mode == "entra":
            from azure.identity import DefaultAzureCredential

            credential = DefaultAzureCredential()

            @event.listens_for(engine, "do_connect")
            def _inject_token(dialect, conn_rec, cargs, cparams):
                cparams["password"] = credential.get_token(PG_ENTRA_SCOPE).token

        else:
            password = s.read_secret_file(s.db_password_file) or s.db_password

            @event.listens_for(engine, "do_connect")
            def _inject_password(dialect, conn_rec, cargs, cparams):
                if password:
                    cparams["password"] = password

        return engine

    def session(self) -> Iterator[Session]:
        """FastAPI dependency: one session per request, committed by the handler."""
        with self.session_factory() as session:
            yield session

    def ping(self) -> None:
        with self.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
