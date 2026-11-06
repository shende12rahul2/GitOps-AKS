import os

import httpx
import pytest

BASE = os.getenv("INTEGRATION_BASE_URL")
KEY = os.getenv("INTERNAL_API_KEY", "")
pytestmark = pytest.mark.skipif(not BASE, reason="INTEGRATION_BASE_URL not set")


def test_order_end_to_end():
    h = {"X-API-Key": KEY}
    with httpx.Client(base_url=BASE, timeout=15) as c:
        r = c.post("/api/orders", json={"user_id": 1, "items": [{"product_id": 1, "quantity": 1}]}, headers=h)
        assert r.status_code == 201, r.text
        oid = r.json()["id"]
        processed = c.post(f"/api/orders/{oid}/process", headers=h).json()
        assert processed["status"] == "PROCESSED" and processed["notification_id"]
