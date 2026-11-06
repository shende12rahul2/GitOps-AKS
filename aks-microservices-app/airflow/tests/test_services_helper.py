import pytest

from aks_poc import services


def test_conn_ids():
    assert services.conn_id("order-service") == "order_service"


def test_authenticated_calls_need_key(monkeypatch):
    monkeypatch.delenv("INTERNAL_API_KEY", raising=False)
    with pytest.raises(RuntimeError):
        services._headers(authenticated=True)
    monkeypatch.setenv("INTERNAL_API_KEY", "k")
    assert services._headers(authenticated=True)["X-API-Key"] == "k"
    assert "X-API-Key" not in services._headers(authenticated=False)
