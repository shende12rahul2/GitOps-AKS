def test_create_order_reserves_stock_and_totals(client, auth, downstream):
    r = client.post(
        "/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 2}, {"product_id": 11, "quantity": 1}]}, headers=auth
    )
    assert r.status_code == 201, r.text
    order = r.json()
    assert order["status"] == "PENDING" and order["total_cents"] == 2 * 500 + 250
    assert downstream.products[10]["stock"] == 1 and downstream.products[11]["stock"] == 0


def test_failed_reservation_is_compensated(client, auth, downstream):
    r = client.post(
        "/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 2}, {"product_id": 11, "quantity": 5}]}, headers=auth
    )
    assert r.status_code == 409
    assert downstream.products[10]["stock"] == 3  # released after product 11 failed


def test_unknown_user_rejected_and_user_lookup_cached(client, auth, downstream):
    assert client.post("/api/orders", json={"user_id": 99, "items": [{"product_id": 10, "quantity": 1}]}, headers=auth).status_code == 422
    for _ in range(2):
        client.post("/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 1}]}, headers=auth)
    assert downstream.user_calls == 2  # 99 (miss) + 1 (miss, then cached)


def test_process_order_sends_notification(client, auth, downstream):
    oid = client.post("/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 1}]}, headers=auth).json()["id"]
    r = client.post(f"/api/orders/{oid}/process", headers=auth)
    assert r.json()["status"] == "PROCESSED" and r.json()["notification_id"] == "n-1"
    assert downstream.notifications[0]["recipient"] == "ada@example.com"
    # idempotent
    assert client.post(f"/api/orders/{oid}/process", headers=auth).json()["notification_id"] == "n-1"
    assert len(downstream.notifications) == 1


def test_process_pending_batch_marks_failures(client, auth, downstream):
    for _ in range(2):
        client.post("/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 1}]}, headers=auth)
    downstream.fail_notifications = True
    result = client.post("/api/orders/process-pending", headers=auth).json()
    assert result["processed"] == [] and len(result["failed"]) == 2
    assert {o["status"] for o in client.get("/api/orders").json()} == {"FAILED"}


def test_write_endpoints_require_key(client):
    assert client.post("/api/orders", json={"user_id": 1, "items": [{"product_id": 10, "quantity": 1}]}).status_code == 401
    assert client.post("/api/orders/process-pending").status_code == 401
