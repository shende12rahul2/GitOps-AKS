import os

import httpx
import pytest

BASE = os.getenv("INTEGRATION_BASE_URL")
KEY = os.getenv("INTERNAL_API_KEY", "")
pytestmark = pytest.mark.skipif(not BASE, reason="INTEGRATION_BASE_URL not set")


def test_cache_against_real_redis():
    with httpx.Client(base_url=BASE, timeout=10) as c:
        ready = c.get("/healthz/ready").json()
        assert ready["checks"]["redis"]["status"] == "ok"
        products = c.get("/api/products").json()
        pid = products[0]["id"]
        c.get(f"/api/products/{pid}")
        assert c.get(f"/api/products/{pid}").headers["X-Cache"] == "HIT"
        c.put(f"/api/products/{pid}", json={"description": "updated by integration test"}, headers={"X-API-Key": KEY})
        assert c.get(f"/api/products/{pid}").headers["X-Cache"] == "MISS"
