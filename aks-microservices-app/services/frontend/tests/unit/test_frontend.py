import re


def test_dashboard_renders_backend_data_and_shared_files(client):
    r = client.get("/")
    assert r.status_code == 200
    html = r.text
    assert "Ada Lovelace" in html and "Keyboard" in html and "PROCESSED" in html
    assert "cache: HIT" in html
    assert "written by notif-0 on aks-apps-2" in html  # read from the shared volume
    assert "default-src 'self'" in r.headers["Content-Security-Policy"]


def test_order_form_requires_matching_csrf_token(client):
    page = client.get("/")
    token = re.search(r'name="csrf_token" value="([^"]+)"', page.text).group(1)
    ok = client.post("/orders", data={"user_id": 1, "product_id": 1, "quantity": 1, "csrf_token": token}, follow_redirects=False)
    assert ok.status_code == 303 and "Order+42+created" in ok.headers["location"]
    client.cookies.clear()
    bad = client.post("/orders", data={"user_id": 1, "product_id": 1, "quantity": 1, "csrf_token": token}, follow_redirects=False)
    assert "Session+expired" in bad.headers["location"]


def test_health_and_static(client):
    assert client.get("/healthz/ready").status_code == 200
    assert client.get("/static/style.css").status_code == 200
    assert client.get("/frontend/info").json()["service"] == "frontend"
