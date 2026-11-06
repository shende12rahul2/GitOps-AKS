import os

import httpx
import pytest

BASE = os.getenv("INTEGRATION_BASE_URL")
KEY = os.getenv("INTERNAL_API_KEY", "")
pytestmark = pytest.mark.skipif(not BASE, reason="INTEGRATION_BASE_URL not set")


def test_notification_round_trip():
    with httpx.Client(base_url=BASE, timeout=10) as c:
        r = c.post("/api/notifications", json={"subject": "it", "message": "integration"}, headers={"X-API-Key": KEY})
        assert r.status_code == 201
        assert c.get(f"/api/notifications/{r.json()['id']}").json()["message"] == "integration"
