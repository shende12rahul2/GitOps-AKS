def test_item_cache_miss_then_hit_and_ttl(client, product, redis_client):
    pid = product["id"]
    r1 = client.get(f"/api/products/{pid}")
    assert r1.headers["X-Cache"] == "MISS"
    r2 = client.get(f"/api/products/{pid}")
    assert r2.headers["X-Cache"] == "HIT" and r2.json() == r1.json()
    ttl = redis_client.ttl(f"app:product-service:item:{pid}")
    assert 0 < ttl <= 60  # every key expires (NoEviction policy)


def test_update_invalidates_item_and_list(client, product, auth):
    pid = product["id"]
    client.get(f"/api/products/{pid}")
    client.get("/api/products")
    assert client.get("/api/products").headers["X-Cache"] == "HIT"
    client.put(f"/api/products/{pid}", json={"price_cents": 1500}, headers=auth)
    r = client.get(f"/api/products/{pid}")
    assert r.headers["X-Cache"] == "MISS" and r.json()["price_cents"] == 1500
    lst = client.get("/api/products")
    assert lst.headers["X-Cache"] == "MISS" and lst.json()[0]["price_cents"] == 1500


def test_reserve_and_release_stock(client, product, auth):
    pid = product["id"]
    assert client.post(f"/api/products/{pid}/reserve", json={"quantity": 3}, headers=auth).json()["stock"] == 2
    assert client.post(f"/api/products/{pid}/reserve", json={"quantity": 3}, headers=auth).status_code == 409
    assert client.post(f"/api/products/{pid}/release", json={"quantity": 3}, headers=auth).json()["stock"] == 5
    assert client.post("/api/products/999/reserve", json={"quantity": 1}, headers=auth).status_code == 404


def test_cache_stats(client, product):
    client.get(f"/api/products/{product['id']}")
    client.get(f"/api/products/{product['id']}")
    stats = client.get("/api/products/cache/stats").json()
    assert stats["hits"] == 1 and stats["misses"] == 1 and stats["hit_ratio"] == 0.5


def test_writes_require_key(client):
    assert client.post("/api/products", json={"sku": "x", "name": "x", "price_cents": 1}).status_code == 401


def test_works_without_redis(tmp_path, auth):
    from fastapi.testclient import TestClient

    from app.main import Settings, build
    from svc_common.db import Base

    app = build(
        Settings(database_url="sqlite+pysqlite:///:memory:", redis_enabled=False, internal_api_keys="test-key", internal_api_keys_file=None)
    )
    Base.metadata.create_all(app.state.db.engine)
    c = TestClient(app)
    c.post("/api/products", json={"sku": "A", "name": "A", "price_cents": 1}, headers=auth)
    assert c.get("/api/products").headers["X-Cache"] == "BYPASS"
    assert c.get("/healthz/ready").json()["checks"].keys() == {"postgres"}
