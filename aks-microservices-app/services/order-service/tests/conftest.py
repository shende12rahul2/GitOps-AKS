import json

import fakeredis
import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import Settings, build
from svc_common.db import Base

API_KEY = "test-key"


class FakeDownstream:
    """In-memory User/Product/Notification services behind httpx.MockTransport."""

    def __init__(self):
        self.users = {1: {"id": 1, "email": "ada@example.com", "full_name": "Ada"}}
        self.products = {10: {"id": 10, "price_cents": 500, "stock": 3}, 11: {"id": 11, "price_cents": 250, "stock": 1}}
        self.notifications = []
        self.user_calls = 0
        self.fail_notifications = False

    def handler(self, request: httpx.Request) -> httpx.Response:
        host, path = request.url.host, request.url.path
        if host == "user-service":
            self.user_calls += 1
            uid = int(path.rsplit("/", 1)[1])
            return (
                httpx.Response(200, json=self.users[uid]) if uid in self.users else httpx.Response(404, json={"detail": "user not found"})
            )
        if host == "product-service":
            assert request.headers.get("X-API-Key") == API_KEY
            pid, action = int(path.split("/")[3]), path.split("/")[4]
            qty = json.loads(request.content)["quantity"]
            p = self.products.get(pid)
            if not p:
                return httpx.Response(404, json={"detail": "product not found"})
            if action == "reserve":
                if p["stock"] < qty:
                    return httpx.Response(409, json={"detail": "insufficient stock"})
                p["stock"] -= qty
            else:
                p["stock"] += qty
            return httpx.Response(200, json=p)
        if host == "notification-service":
            if self.fail_notifications:
                return httpx.Response(503, json={"detail": "down"})
            body = json.loads(request.content)
            self.notifications.append(body)
            return httpx.Response(201, json={"id": f"n-{len(self.notifications)}", **body})
        return httpx.Response(500)


@pytest.fixture()
def downstream():
    return FakeDownstream()


@pytest.fixture()
def client(downstream):
    settings = Settings(database_url="sqlite+pysqlite:///:memory:", internal_api_keys=API_KEY, internal_api_keys_file=None)
    app = build(settings, redis_client=fakeredis.FakeRedis(), transport=httpx.MockTransport(downstream.handler))
    Base.metadata.create_all(app.state.db.engine)
    return TestClient(app)


@pytest.fixture()
def auth():
    return {"X-API-Key": API_KEY}
