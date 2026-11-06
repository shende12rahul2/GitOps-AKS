"""Runs against the real HTTPS entry point: APP_URL=https://app.poc.example.com"""

import os

import httpx
import pytest

APP = os.getenv("APP_URL")
CA = os.getenv("APP_CA_BUNDLE", True)
pytestmark = pytest.mark.skipif(not APP, reason="APP_URL not set")


def test_https_dashboard_and_routing():
    with httpx.Client(base_url=APP, verify=CA, timeout=15, follow_redirects=False) as c:
        r = c.get("/")
        assert r.status_code == 200 and "AKS POC Shop" in r.text
        assert "max-age" in r.headers.get("Strict-Transport-Security", "")
        for path in ("/api/users", "/api/products", "/api/orders", "/api/notifications"):
            assert c.get(path).status_code == 200, path
    plain = httpx.get(APP.replace("https://", "http://"), verify=CA, follow_redirects=False, timeout=15)
    assert plain.status_code in (301, 302, 307, 308)
