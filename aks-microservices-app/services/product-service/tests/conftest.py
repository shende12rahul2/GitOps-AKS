import fakeredis
import pytest
from fastapi.testclient import TestClient

from app.main import Settings, build
from svc_common.db import Base

API_KEY = "test-key"


@pytest.fixture()
def redis_client():
    return fakeredis.FakeRedis()


@pytest.fixture()
def client(tmp_path, redis_client):
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        internal_api_keys=API_KEY,
        internal_api_keys_file=None,
        cache_item_ttl_seconds=60,
        cache_list_ttl_seconds=30,
    )
    app = build(settings, redis_client=redis_client)
    Base.metadata.create_all(app.state.db.engine)
    return TestClient(app)


@pytest.fixture()
def auth():
    return {"X-API-Key": API_KEY}


@pytest.fixture()
def product(client, auth):
    r = client.post("/api/products", json={"sku": "T-1", "name": "Thing", "price_cents": 1000, "stock": 5}, headers=auth)
    assert r.status_code == 201, r.text
    return r.json()
