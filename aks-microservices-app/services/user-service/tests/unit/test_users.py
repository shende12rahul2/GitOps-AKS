def test_create_read_update_user(client, auth):
    r = client.post("/api/users", json={"email": "Jane@Example.com", "full_name": "Jane"}, headers=auth)
    assert r.status_code == 201, r.text
    user = r.json()
    assert user["email"] == "jane@example.com"

    assert client.get(f"/api/users/{user['id']}").json()["full_name"] == "Jane"
    r = client.put(f"/api/users/{user['id']}", json={"full_name": "Jane Doe"}, headers=auth)
    assert r.json()["full_name"] == "Jane Doe"
    assert [u["id"] for u in client.get("/api/users").json()] == [user["id"]]


def test_writes_require_api_key(client):
    assert client.post("/api/users", json={"email": "a@b.co", "full_name": "A"}).status_code == 401
    assert client.put("/api/users/1", json={"full_name": "A"}).status_code == 401


def test_duplicate_email_conflict(client, auth):
    body = {"email": "dup@example.com", "full_name": "Dup"}
    assert client.post("/api/users", json=body, headers=auth).status_code == 201
    assert client.post("/api/users", json=body, headers=auth).status_code == 409


def test_validation_and_not_found(client, auth):
    assert client.post("/api/users", json={"email": "not-an-email", "full_name": "x"}, headers=auth).status_code == 422
    assert client.get("/api/users/999").status_code == 404


def test_health_and_shared_storage(client):
    r = client.get("/healthz/ready")
    assert r.status_code == 200 and r.json()["checks"]["postgres"]["status"] == "ok"
    assert client.get("/api/users/shared/selftest").json()["consistent"] is True
