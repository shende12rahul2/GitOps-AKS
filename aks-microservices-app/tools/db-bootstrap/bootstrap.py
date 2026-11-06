"""Idempotent PostgreSQL bootstrap for Azure Database for PostgreSQL Flexible Server.

Runs in-cluster as an Argo CD PreSync/sync-wave Job, authenticated as the
server's Microsoft Entra administrator (workload identity "db-bootstrap").
Terraform cannot do this: databases created through ARM are owned by an
internal role, so an Entra administrator could not create schemas or grant
privileges in them. Everything here is plain SQL, versioned in Git and
re-runnable at any time (it converges, it never drops).

For each environment (config file, mounted from a ConfigMap):
  1. principals  - Entra roles mapped to managed identities / groups via
                   pgaadauth_create_principal_with_oid(); password roles (Airflow)
                   whose password is read from a Key Vault CSI file and re-synced
                   every run (rotation = change the Key Vault secret, re-sync).
  2. databases   - CREATE DATABASE as the Entra admin, REVOKE ALL FROM PUBLIC,
                   CONNECT/TEMP for the owning application role only.
  3. schema      - USAGE+CREATE on the schema for the owning role; USAGE for the
                   <db>_readonly role. The application migrates its own tables
                   and grants SELECT to <db>_readonly in its migrations.
  4. readers     - Entra groups (QA/developers in non-prod) receive <db>_readonly.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import psycopg
import yaml
from psycopg import sql

log = logging.getLogger("db-bootstrap")
PG_ENTRA_SCOPE = "https://ossrdbms-aad.database.windows.net/.default"


@dataclass
class Principal:
    key: str
    role: str
    type: str  # entra-service | entra-group | password
    object_id: str | None = None
    password_file: str | None = None
    connection_limit: int | None = None


@dataclass
class DatabaseSpec:
    name: str
    owner: str  # principal key
    schema: str = "public"
    readers: list[str] = field(default_factory=list)  # principal keys


@dataclass
class Config:
    principals: dict[str, Principal]
    databases: list[DatabaseSpec]

    @classmethod
    def load(cls, path: str) -> Config:
        raw = yaml.safe_load(Path(path).read_text())
        principals = {k: Principal(key=k, **v) for k, v in raw["principals"].items()}
        dbs = [DatabaseSpec(**d) for d in raw["databases"]]
        for d in dbs:
            for ref in [d.owner, *d.readers]:
                if ref not in principals:
                    raise ValueError(f"database {d.name} references unknown principal {ref}")
        return cls(principals, dbs)


def admin_password(args: argparse.Namespace) -> str:
    if args.auth == "entra":
        from azure.identity import DefaultAzureCredential

        return DefaultAzureCredential().get_token(PG_ENTRA_SCOPE).token
    return Path(args.admin_password_file).read_text().strip() if args.admin_password_file else os.environ.get("PGPASSWORD", "")


def connect(args: argparse.Namespace, dbname: str) -> psycopg.Connection:
    return psycopg.connect(
        host=args.host,
        port=args.port,
        dbname=dbname,
        user=args.admin_user,
        password=admin_password(args),
        sslmode=args.sslmode,
        autocommit=True,
        connect_timeout=15,
        application_name="db-bootstrap",
    )


def role_exists(cur: psycopg.Cursor, role: str) -> bool:
    cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,))
    return cur.fetchone() is not None


def ensure_principal(cur: psycopg.Cursor, p: Principal, report: dict) -> None:
    ident = sql.Identifier(p.role)
    if p.type in ("entra-service", "entra-group"):
        if not role_exists(cur, p.role):
            kind = "service" if p.type == "entra-service" else "group"
            # Maps the PostgreSQL role to the Entra object ID (immune to renames).
            cur.execute("SELECT * FROM pgaadauth_create_principal_with_oid(%s, %s, %s, false, false)", (p.role, p.object_id, kind))
            report["created_roles"].append(p.role)
    elif p.type == "password":
        password = Path(p.password_file).read_text().strip()
        if not password:
            raise ValueError(f"empty password file for {p.role}")
        verb = "ALTER" if role_exists(cur, p.role) else "CREATE"
        cur.execute(
            sql.SQL(verb + " ROLE {} WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD {}").format(ident, sql.Literal(password))
        )
        report["password_synced"].append(p.role)
        if verb == "CREATE":
            report["created_roles"].append(p.role)
    elif p.type == "local-login":  # local/integration testing only (no Entra)
        if not role_exists(cur, p.role):
            cur.execute(sql.SQL("CREATE ROLE {} WITH LOGIN PASSWORD {}").format(ident, sql.Literal(p.role)))
            report["created_roles"].append(p.role)
    else:
        raise ValueError(f"unknown principal type {p.type}")
    if p.connection_limit is not None and p.type == "password":
        cur.execute(sql.SQL("ALTER ROLE {} CONNECTION LIMIT {}").format(ident, sql.Literal(p.connection_limit)))


def ensure_database(args: argparse.Namespace, cur: psycopg.Cursor, d: DatabaseSpec, cfg: Config, report: dict) -> None:
    owner = sql.Identifier(cfg.principals[d.owner].role)
    readonly_name = f"{d.name}_readonly"
    readonly = sql.Identifier(readonly_name)
    db = sql.Identifier(d.name)

    if not role_exists(cur, readonly_name):
        cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(readonly))
        report["created_roles"].append(readonly_name)

    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (d.name,))
    if cur.fetchone() is None:
        cur.execute(sql.SQL("CREATE DATABASE {} ENCODING 'UTF8' TEMPLATE template0").format(db))
        report["created_databases"].append(d.name)

    cur.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(db))
    cur.execute(sql.SQL("GRANT CONNECT, TEMPORARY ON DATABASE {} TO {}").format(db, owner))
    cur.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(db, readonly))

    for reader_key in d.readers:
        cur.execute(sql.SQL("GRANT {} TO {}").format(readonly, sql.Identifier(cfg.principals[reader_key].role)))

    with connect(args, d.name) as dbconn, dbconn.cursor() as dcur:
        schema = sql.Identifier(d.schema)
        if d.schema != "public":
            dcur.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(schema))
        dcur.execute(sql.SQL("REVOKE CREATE ON SCHEMA {} FROM PUBLIC").format(schema))
        dcur.execute(sql.SQL("GRANT USAGE, CREATE ON SCHEMA {} TO {}").format(schema, owner))
        dcur.execute(sql.SQL("GRANT USAGE ON SCHEMA {} TO {}").format(schema, readonly))
    report["configured_databases"].append(d.name)


def run(args: argparse.Namespace) -> dict:
    cfg = Config.load(args.config)
    report = {"created_roles": [], "password_synced": [], "created_databases": [], "configured_databases": []}
    with connect(args, "postgres") as conn, conn.cursor() as cur:
        for p in cfg.principals.values():
            ensure_principal(cur, p, report)
        for d in cfg.databases:
            ensure_database(args, cur, d, cfg, report)
    return report


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    env = os.environ.get
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--config", default=env("BOOTSTRAP_CONFIG", "/config/bootstrap.yaml"))
    parser.add_argument("--host", default=env("PGHOST", "localhost"))
    parser.add_argument("--port", type=int, default=int(env("PGPORT", "5432")))
    parser.add_argument("--admin-user", default=env("PGUSER", "postgres"), help="Entra admin role name (managed identity display name)")
    parser.add_argument("--auth", choices=["entra", "password"], default=env("PG_AUTH_MODE", "entra"))
    parser.add_argument("--admin-password-file", default=env("PG_ADMIN_PASSWORD_FILE"))
    parser.add_argument("--sslmode", default=env("PGSSLMODE", "require"))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format='{"level":"%(levelname)s","logger":"%(name)s","message":"%(message)s"}')
    args = parse_args(argv)
    try:
        report = run(args)
    except Exception as exc:  # noqa: BLE001 - Job must fail loudly with a clear message
        log.error("bootstrap failed: %s", exc)
        return 1
    print(json.dumps({"status": "ok", **report}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
