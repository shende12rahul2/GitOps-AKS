"""Versioned SQL migrations (no ORM autogeneration).

Files: migrations/NNN_description.sql, applied in order inside a transaction
each. Applied versions and SHA-256 checksums are recorded in schema_migrations;
editing an already-applied file fails the run (immutable history). A PostgreSQL
advisory lock serialises concurrent runners (e.g. two Job pods).

Run: python -m svc_common.migrate --dir /app/migrations
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import re
import sys
from pathlib import Path

from sqlalchemy import Engine, text

from .config import CommonSettings
from .db import Database
from .logging import configure_logging

log = logging.getLogger("migrate")
FILE_RE = re.compile(r"^(\d{3,})_[a-z0-9_]+\.sql$")
LOCK_KEY = 7_212_026  # arbitrary, per database


class MigrationError(RuntimeError):
    pass


def discover(directory: Path) -> list[tuple[str, Path]]:
    files = []
    for path in sorted(directory.iterdir()):
        m = FILE_RE.match(path.name)
        if m:
            files.append((m.group(1), path))
        elif path.suffix == ".sql":
            raise MigrationError(f"invalid migration file name: {path.name}")
    versions = [v for v, _ in files]
    if len(versions) != len(set(versions)):
        raise MigrationError("duplicate migration versions")
    return files


def checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def split_statements(sql: str) -> list[str]:
    """Split on semicolons outside quotes/comments (migrations avoid $$ bodies)."""
    statements, buf, quote = [], [], None
    lines = [ln for ln in sql.splitlines() if not ln.strip().startswith("--")]
    for ch in "\n".join(lines):
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        if ch == ";":
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
            continue
        buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def migrate(engine: Engine, directory: Path) -> list[str]:
    applied_now: list[str] = []
    is_pg = engine.dialect.name == "postgresql"
    with engine.connect() as conn:
        if is_pg:
            conn.execute(text("SELECT pg_advisory_lock(:k)"), {"k": LOCK_KEY})
        try:
            conn.execute(
                text(
                    "CREATE TABLE IF NOT EXISTS schema_migrations ("
                    " version VARCHAR(32) PRIMARY KEY,"
                    " checksum VARCHAR(64) NOT NULL,"
                    " applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
                )
            )
            conn.commit()
            done = {r.version: r.checksum for r in conn.execute(text("SELECT version, checksum FROM schema_migrations"))}
            conn.commit()  # end the autobegun read transaction; each migration gets its own
            for version, path in discover(directory):
                digest = checksum(path)
                if version in done:
                    if done[version] != digest:
                        raise MigrationError(f"{path.name} was modified after it was applied")
                    continue
                with conn.begin():
                    for stmt in split_statements(path.read_text(encoding="utf-8")):
                        conn.execute(text(stmt))
                    conn.execute(
                        text("INSERT INTO schema_migrations (version, checksum) VALUES (:v, :c)"),
                        {"v": version, "c": digest},
                    )
                log.info("applied migration", extra={"migration": path.name})
                applied_now.append(path.name)
        finally:
            if is_pg:
                conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": LOCK_KEY})
                conn.commit()
    return applied_now


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Apply versioned SQL migrations")
    parser.add_argument("--dir", default="/app/migrations")
    args = parser.parse_args(argv)
    settings = CommonSettings()
    configure_logging(settings.service_name, settings.environment, settings.log_level, settings.pod_name, settings.node_name)
    try:
        applied = migrate(Database(settings).engine, Path(args.dir))
    except MigrationError as exc:
        log.error("migration failed", extra={"error": str(exc)})
        return 1
    log.info("migrations complete", extra={"applied": applied})
    return 0


if __name__ == "__main__":
    sys.exit(main())
