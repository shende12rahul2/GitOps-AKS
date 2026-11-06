"""Frontend: server-side rendered dashboard.

The browser only talks to the frontend over HTTPS through the ingress. Data is
fetched server-side from the backend Services (ClusterIP, cluster DNS), and the
latest notifications are read directly from the shared Azure Files volume
(written by notification-service, possibly on another node).
"""

from __future__ import annotations

import hmac
import json
import logging
import secrets
from functools import cached_property
from pathlib import Path

import httpx
from fastapi import Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from svc_common.app import create_app, shared_storage_router
from svc_common.config import CommonSettings
from svc_common.http import ServiceClient
from svc_common.shared_storage import SharedStorage

log = logging.getLogger("frontend")
HERE = Path(__file__).parent
CSP = "default-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'self'"


class Settings(CommonSettings):
    service_name: str = "frontend"
    db_enabled: bool = False
    user_service_url: str = "http://user-service:8000"
    product_service_url: str = "http://product-service:8000"
    order_service_url: str = "http://order-service:8000"
    secure_cookies: bool = True

    @cached_property
    def api_prefix(self) -> str:
        return "/frontend"


def build(settings: Settings | None = None, transport: httpx.BaseTransport | None = None):
    settings = settings or Settings()
    app, keys = create_app(settings, "Frontend")
    templates = Jinja2Templates(directory=str(HERE / "templates"))
    app.mount("/static", StaticFiles(directory=str(HERE / "static")), name="static")

    users = ServiceClient(settings.user_service_url, keys, transport=transport)
    products = ServiceClient(settings.product_service_url, keys, transport=transport)
    orders = ServiceClient(settings.order_service_url, keys, transport=transport)
    storage = SharedStorage(settings.shared_mount_path, settings.service_name)

    def fetch(client: ServiceClient, path: str) -> tuple[list, str | None]:
        try:
            r = client.get(path)
            r.raise_for_status()
            return r.json(), r.headers.get("X-Cache")
        except httpx.HTTPError as exc:
            log.warning("backend call failed", extra={"path": path, "error": str(exc)})
            return [], "ERROR"

    def latest_notifications(limit: int = 5) -> list[dict]:
        if not settings.shared_storage_enabled:
            return []
        out = []
        for f in storage.list_files("notification-service", "outbox", limit=limit):
            try:
                out.append(json.loads(storage.read_text("notification-service", f["path"])))
            except (FileNotFoundError, json.JSONDecodeError):
                continue
        return out

    @app.get("/", response_class=HTMLResponse)
    def dashboard(request: Request, message: str | None = None):
        user_list, _ = fetch(users, "/api/users")
        product_list, cache_status = fetch(products, "/api/products")
        order_list, _ = fetch(orders, "/api/orders?limit=10")
        token = secrets.token_urlsafe(32)
        response = templates.TemplateResponse(
            request,
            "index.html",
            {
                "users": user_list,
                "products": product_list,
                "orders": order_list,
                "notifications": latest_notifications(),
                "cache_status": cache_status,
                "csrf_token": token,
                "message": message,
                "settings": settings,
            },
        )
        response.set_cookie("csrf", token, httponly=True, samesite="strict", secure=settings.secure_cookies, max_age=3600)
        response.headers["Content-Security-Policy"] = CSP
        return response

    @app.post("/orders")
    def create_order(
        request: Request, user_id: int = Form(...), product_id: int = Form(...), quantity: int = Form(1), csrf_token: str = Form(...)
    ):
        cookie = request.cookies.get("csrf", "")
        if not cookie or not hmac.compare_digest(cookie, csrf_token):
            return RedirectResponse("/?message=Session+expired,+please+retry", status_code=303)
        try:
            r = orders.post("/api/orders", json={"user_id": user_id, "items": [{"product_id": product_id, "quantity": quantity}]})
            msg = f"Order {r.json()['id']} created" if r.status_code == 201 else f"Order rejected: {r.json().get('detail')}"
        except httpx.HTTPError:
            msg = "Order service unavailable"
        return RedirectResponse(f"/?message={msg.replace(' ', '+')}", status_code=303)

    router, _ = shared_storage_router(settings, keys)
    app.include_router(router)
    return app
