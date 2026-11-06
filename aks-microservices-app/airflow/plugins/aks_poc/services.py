"""Calls the POC microservices from Airflow tasks.

Connections (one per service) are provided as environment variables by the Helm
values, e.g. AIRFLOW_CONN_ORDER_SERVICE='{"conn_type": "http", "host":
"order-service.apps.svc.cluster.local", "port": 8000, "schema": "http"}'.
The service API key comes from the Key Vault secret "internal-api-key",
synced to the Kubernetes secret airflow-internal-api (env INTERNAL_API_KEY).
Nothing secret is stored in DAG code, Airflow Variables or the metadata DB.
"""

from __future__ import annotations

import json
import os
from typing import Any

SERVICES = {
    "user-service": "/api/users",
    "product-service": "/api/products",
    "order-service": "/api/orders",
    "notification-service": "/api/notifications",
}


def conn_id(service: str) -> str:
    return service.replace("-", "_")


def _headers(authenticated: bool) -> dict[str, str]:
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if authenticated:
        key = os.environ.get("INTERNAL_API_KEY", "").strip()
        if not key:
            raise RuntimeError("INTERNAL_API_KEY is not set (Key Vault secret internal-api-key)")
        headers["X-API-Key"] = key
    return headers


def call(service: str, method: str, path: str, payload: Any | None = None, authenticated: bool = False, timeout: int = 30) -> Any:
    from airflow.providers.http.hooks.http import HttpHook

    hook = HttpHook(method=method, http_conn_id=conn_id(service))
    response = hook.run(
        endpoint=path,
        data=json.dumps(payload) if payload is not None else None,
        headers=_headers(authenticated),
        extra_options={"timeout": timeout, "check_response": True},
    )
    return response.json() if response.content else None
