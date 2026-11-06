import json


def test_notification_written_atomically_to_shared_storage(client, auth, tmp_path):
    r = client.post("/api/notifications", json={"order_id": 7, "subject": "Hi", "message": "Order 7 done"}, headers=auth)
    assert r.status_code == 201, r.text
    body = r.json()
    path = tmp_path / body["path"]
    assert json.loads(path.read_text())["order_id"] == 7
    assert body["written_by"] == {"pod": "notif-1", "node": "node-a"}
    assert not list(path.parent.glob(".*.tmp"))


def test_list_get_and_daily_summary(client, auth):
    ids = [client.post("/api/notifications", json={"subject": f"s{i}", "message": "m"}, headers=auth).json()["id"] for i in range(3)]
    listing = client.get("/api/notifications").json()
    assert listing["count"] == 3
    assert client.get(f"/api/notifications/{ids[0]}").json()["subject"] == "s0"
    assert client.get("/api/notifications/summary/today").json()["count"] == 3
    assert client.get("/api/notifications/deadbeef").status_code == 404
    assert client.get("/api/notifications/..%2Fx").status_code in (400, 404)


def test_requires_key_and_validates(client, auth):
    assert client.post("/api/notifications", json={"subject": "s", "message": "m"}).status_code == 401
    assert client.post("/api/notifications", json={"subject": "", "message": "m"}, headers=auth).status_code == 422


def test_cross_service_read_through_shared_router(client, auth, tmp_path):
    (tmp_path / "order-service").mkdir(exist_ok=True)
    (tmp_path / "order-service" / "report.txt").write_text("from order-service")
    r = client.get("/api/notifications/shared/files/order-service/report.txt", headers=auth)
    assert r.text == "from order-service" and r.headers["X-Served-By-Node"] == "node-a"
