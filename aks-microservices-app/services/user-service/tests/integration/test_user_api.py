"""Integration tests against a running stack (docker compose or AKS).
Run: INTEGRATION_BASE_URL=http://localhost:8001 INTERNAL_API_KEY=... pytest tests/integration"""

import os
import uuid

import httpx
import pytest

BASE = os.getenv("INTEGRATION_BASE_URL")
KEY = os.getenv("INTERNAL_API_KEY", "")
pytestmark = pytest.mark.skipif(not BASE, reason="INTEGRATION_BASE_URL not set")


def test_user_crud_against_postgres():
    with httpx.Client(base_url=BASE, timeout=10) as c:
        assert c.get("/healthz/ready").status_code == 200
        email = f"it-{uuid.uuid4().hex[:8]}@example.com"
        r = c.post("/api/users", json={"email": email, "full_name": "Integration"}, headers={"X-API-Key": KEY})
        assert r.status_code == 201, r.text
        uid = r.json()["id"]
        r = c.put(f"/api/users/{uid}", json={"full_name": "Integration Updated"}, headers={"X-API-Key": KEY})
        assert r.json()["full_name"] == "Integration Updated"
        assert any(u["email"] == email for u in c.get("/api/users").json())
        # seed data from migration 002
        assert any(u["email"] == "ada.lovelace@example.com" for u in c.get("/api/users").json())
