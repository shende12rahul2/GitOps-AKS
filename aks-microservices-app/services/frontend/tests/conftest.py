import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import Settings, build

API_KEY = "test-key"


def handler(request: httpx.Request) -> httpx.Response:
    host = request.url.host
    if host == "user-service":
        return httpx.Response(200, json=[{"id": 1, "email": "ada@example.com", "full_name": "Ada Lovelace"}])
    if host == "product-service":
        return httpx.Response(
            200, json=[{"id": 1, "sku": "KB-001", "name": "Keyboard", "price_cents": 8900, "stock": 5}], headers={"X-Cache": "HIT"}
        )
    if host == "order-service":
        if request.method == "POST":
            assert request.headers["X-API-Key"] == API_KEY
            return httpx.Response(201, json={"id": 42})
        return httpx.Response(200, json=[{"id": 42, "user_id": 1, "status": "PROCESSED", "total_cents": 8900, "notification_id": "abc"}])
    return httpx.Response(500)


@pytest.fixture()
def client(tmp_path):
    outbox = tmp_path / "notification-service" / "outbox" / "2026" / "11" / "06"
    outbox.mkdir(parents=True)
    (outbox / "abc.json").write_text(
        json.dumps(
            {
                "id": "abc",
                "subject": "Order 42 confirmed",
                "message": "done",
                "created_at": "now",
                "written_by": {"pod": "notif-0", "node": "aks-apps-2"},
            }
        )
    )
    (tmp_path / "frontend").mkdir(exist_ok=True)
    settings = Settings(
        shared_storage_enabled=True,
        shared_mount_path=str(tmp_path),
        internal_api_keys=API_KEY,
        internal_api_keys_file=None,
        secure_cookies=False,
    )
    return TestClient(build(settings, transport=httpx.MockTransport(handler)))
