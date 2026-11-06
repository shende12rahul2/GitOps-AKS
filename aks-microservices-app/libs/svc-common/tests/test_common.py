import contextlib
import json
import os
import threading

import fakeredis
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from svc_common.app import create_app, shared_storage_router
from svc_common.auth import ApiKeyStore
from svc_common.cache import Cache
from svc_common.config import CommonSettings
from svc_common.db import Database
from svc_common.migrate import MigrationError, migrate, split_statements
from svc_common.shared_storage import LockTimeout, SharedStorage, StorageError


def settings(tmp_path, **kw):
    base = dict(
        service_name="user-service",
        internal_api_keys="k1,k2",
        internal_api_keys_file=None,
        database_url="sqlite+pysqlite:///:memory:",
        shared_mount_path=str(tmp_path),
    )
    base.update(kw)
    return CommonSettings(**base)


def test_api_prefix(tmp_path):
    assert settings(tmp_path).api_prefix == "/api/users"
    assert settings(tmp_path, service_name="notification-service").api_prefix == "/api/notifications"


def test_api_keys_rotation_from_file(tmp_path):
    f = tmp_path / "key"
    f.write_text("old\n")
    store = ApiKeyStore(settings(tmp_path, internal_api_keys_file=str(f), internal_api_keys=None))
    assert store.verify("old") and not store.verify("new")
    f.write_text("new\nold\n")
    os.utime(f, (os.stat(f).st_atime, os.stat(f).st_mtime + 5))
    assert store.verify("new") and store.verify("old")
    assert store.primary() == "new"
    assert not store.verify(None)


def test_cache_namespacing_and_ttl():
    r = fakeredis.FakeRedis()
    c = Cache(r, "app:product-service")
    c.set_json("item:1", {"a": 1}, 30)
    assert r.ttl("app:product-service:item:1") <= 30
    assert c.get_json("item:1") == {"a": 1}
    with pytest.raises(ValueError):
        c.set_json("x", 1, 0)  # NoEviction: every key must expire
    assert c.incr("ver") == 1 and c.incr("ver") == 2
    c.delete("item:1")
    assert c.get_json("item:1") is None


def test_cache_degrades_when_redis_down():
    class Broken(fakeredis.FakeRedis):
        def get(self, *a, **k):
            import redis

            raise redis.ConnectionError("down")

    assert Cache(Broken(), "p").get_json("k") is None


def test_shared_storage_atomic_write_and_isolation(tmp_path):
    s = SharedStorage(tmp_path, "order-service")
    s.ensure_layout()
    s.write_json("a/b.json", {"x": 1})
    assert json.loads(s.read_text("order-service", "a/b.json")) == {"x": 1}
    assert not [p for p in (tmp_path / "order-service" / "a").iterdir() if p.name.endswith(".tmp")]
    s.write_text("note.txt", "hi", area="common")
    with pytest.raises(StorageError):
        s.write_text("x", "y", area="user-service")
    with pytest.raises(StorageError):
        s.read_text("..", "etc/passwd")


def test_exclusive_lock_is_mutually_exclusive(tmp_path):
    a = SharedStorage(tmp_path, "user-service")
    b = SharedStorage(tmp_path, "product-service")
    with a.exclusive_lock("report"), pytest.raises(LockTimeout), b.exclusive_lock("report", timeout=0.3):
        pass
    with b.exclusive_lock("report", timeout=0.3):
        pass


def test_concurrent_writers_never_produce_partial_files(tmp_path):
    s = SharedStorage(tmp_path, "notification-service")
    payload = "x" * 200_000

    def writer():
        for _ in range(20):
            s.write_text("shared.txt", payload)

    threads = [threading.Thread(target=writer) for _ in range(4)]
    for t in threads:
        t.start()
    for _ in range(50):
        with contextlib.suppress(FileNotFoundError):
            assert len(s.read_text("notification-service", "shared.txt")) == len(payload)
    for t in threads:
        t.join()


def test_migrations_apply_once_and_detect_tampering(tmp_path):
    mig = tmp_path / "migrations"
    mig.mkdir()
    (mig / "001_init.sql").write_text("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\n-- comment\nINSERT INTO t (v) VALUES ('a;b');")
    db = Database(settings(tmp_path))
    assert migrate(db.engine, mig) == ["001_init.sql"]
    assert migrate(db.engine, mig) == []
    with db.engine.connect() as c:
        assert c.execute(text("SELECT v FROM t")).scalar() == "a;b"
    (mig / "001_init.sql").write_text("CREATE TABLE t2 (id INTEGER);")
    with pytest.raises(MigrationError):
        migrate(db.engine, mig)


def test_split_statements_respects_quotes():
    assert split_statements("SELECT 'a;b'; SELECT 2;") == ["SELECT 'a;b'", "SELECT 2"]


def test_app_health_auth_and_shared_endpoints(tmp_path):
    st = settings(tmp_path, shared_storage_enabled=True)
    failing = {"db": lambda: (_ for _ in ()).throw(RuntimeError("down"))}
    app, keys = create_app(st, "t", readiness=failing)
    router, storage = shared_storage_router(st, keys)
    storage.ensure_layout()
    app.include_router(router)
    c = TestClient(app)
    assert c.get("/healthz/live").json() == {"status": "ok"}
    r = c.get("/healthz/ready")
    assert r.status_code == 503 and r.json()["checks"]["db"]["status"] == "error"
    r = c.get("/api/users/info")
    assert r.headers["Strict-Transport-Security"].startswith("max-age=")
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert c.put("/api/users/shared/files/common/x.txt", content=b"hello").status_code == 401
    r = c.put("/api/users/shared/files/common/x.txt", content=b"hello", headers={"X-API-Key": "k2"})
    assert r.status_code == 200, r.text
    assert c.get("/api/users/shared/files/common/x.txt", headers={"X-API-Key": "k1"}).text == "hello"
    assert c.put("/api/users/shared/files/order-service/x.txt", content=b"no", headers={"X-API-Key": "k1"}).status_code == 403
    assert c.get("/api/users/shared/selftest").json()["consistent"] is True
    assert "http_requests_total" in c.get("/metrics").text
