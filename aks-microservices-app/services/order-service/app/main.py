"""Order Service: orders in PostgreSQL (orders_db) built from User and Product
Service data, with notifications sent through the Notification Service.

Create order (saga-lite):
  1. validate the user via User Service (cached in Redis for USER_CACHE_TTL)
  2. reserve stock item by item via Product Service (atomic conditional update)
  3. on any failure, release what was reserved (compensation), return 409/424
  4. persist the order as PENDING
Process order: mark PROCESSED and ask Notification Service to write the
notification file to Azure Files.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime

import httpx
from fastapi import Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from svc_common.app import create_app, shared_storage_router
from svc_common.auth import require_api_key
from svc_common.cache import Cache, build_client
from svc_common.config import CommonSettings
from svc_common.db import Database
from svc_common.http import ServiceClient

from .models import Order, OrderItem

log = logging.getLogger("orders")


class Settings(CommonSettings):
    service_name: str = "order-service"
    redis_enabled: bool = True
    redis_key_prefix: str = "app:order-service"
    user_cache_ttl_seconds: int = 300
    user_service_url: str = "http://user-service:8000"
    product_service_url: str = "http://product-service:8000"
    notification_service_url: str = "http://notification-service:8000"


class ItemIn(BaseModel):
    product_id: int
    quantity: int = Field(gt=0, le=100)


class OrderIn(BaseModel):
    user_id: int
    items: list[ItemIn] = Field(min_length=1, max_length=20)


class ItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    product_id: int
    quantity: int
    unit_price_cents: int


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    user_id: int
    status: str
    total_cents: int
    notification_id: str | None
    created_at: datetime | None = None
    processed_at: datetime | None = None
    items: list[ItemOut]


def build(settings: Settings | None = None, redis_client=None, transport: httpx.BaseTransport | None = None):
    settings = settings or Settings()
    db = Database(settings)
    client = redis_client if redis_client is not None else (build_client(settings) if settings.redis_enabled else None)
    cache = Cache(client, settings.redis_key_prefix)
    checks = {"postgres": db.ping}
    if cache.enabled:
        checks["redis"] = cache.ping
    app, keys = create_app(settings, "Order Service", readiness=checks)
    write_auth = [Depends(require_api_key(keys))]
    prefix = settings.api_prefix

    users = ServiceClient(settings.user_service_url, keys, transport=transport)
    products = ServiceClient(settings.product_service_url, keys, transport=transport)
    notifications = ServiceClient(settings.notification_service_url, keys, transport=transport)

    def fetch_user(user_id: int) -> dict:
        if (cached := cache.get_json(f"user:{user_id}")) is not None:
            return cached
        try:
            r = users.get(f"/api/users/{user_id}")
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=status.HTTP_424_FAILED_DEPENDENCY, detail=f"user-service unavailable: {exc}") from exc
        if r.status_code == 404:
            raise HTTPException(status_code=422, detail="unknown user")
        r.raise_for_status()
        user = r.json()
        cache.set_json(f"user:{user_id}", user, settings.user_cache_ttl_seconds)
        return user

    def release_all(reserved: list[tuple[int, int]]) -> None:
        for product_id, qty in reserved:
            try:
                products.post(f"/api/products/{product_id}/release", json={"quantity": qty})
            except httpx.HTTPError:
                log.error("stock release failed; manual reconciliation needed", extra={"product_id": product_id, "quantity": qty})

    @app.get(prefix, response_model=list[OrderOut])
    def list_orders(status_filter: str | None = None, limit: int = 100, session: Session = Depends(db.session)):
        q = select(Order).order_by(Order.id.desc()).limit(min(limit, 500))
        if status_filter:
            q = q.where(Order.status == status_filter.upper())
        return session.scalars(q).all()

    @app.get(prefix + "/{order_id}", response_model=OrderOut)
    def get_order(order_id: int, session: Session = Depends(db.session)):
        order = session.get(Order, order_id)
        if not order:
            raise HTTPException(status_code=404, detail="order not found")
        return order

    @app.post(prefix, response_model=OrderOut, status_code=201, dependencies=write_auth)
    def create_order(body: OrderIn, session: Session = Depends(db.session)):
        fetch_user(body.user_id)
        reserved: list[tuple[int, int]] = []
        lines: list[OrderItem] = []
        try:
            for item in body.items:
                r = products.post(f"/api/products/{item.product_id}/reserve", json={"quantity": item.quantity})
                if r.status_code in (404, 409):
                    raise HTTPException(status_code=409, detail=f"product {item.product_id}: {r.json().get('detail')}")
                r.raise_for_status()
                reserved.append((item.product_id, item.quantity))
                lines.append(OrderItem(product_id=item.product_id, quantity=item.quantity, unit_price_cents=r.json()["price_cents"]))
        except HTTPException:
            release_all(reserved)
            raise
        except httpx.HTTPError as exc:
            release_all(reserved)
            raise HTTPException(status_code=424, detail=f"product-service unavailable: {exc}") from exc

        order = Order(user_id=body.user_id, status="PENDING", items=lines, total_cents=sum(i.quantity * i.unit_price_cents for i in lines))
        session.add(order)
        session.commit()
        session.refresh(order)
        log.info("order created", extra={"order_id": order.id, "total_cents": order.total_cents})
        return order

    def process(order: Order, session: Session) -> Order:
        if order.status == "PROCESSED":
            return order
        user = fetch_user(order.user_id)
        payload = {
            "order_id": order.id,
            "user_id": order.user_id,
            "channel": "email",
            "recipient": user.get("email"),
            "subject": f"Order {order.id} confirmed",
            "message": f"Hello {user.get('full_name')}, your order {order.id} totalling {order.total_cents / 100:.2f} has been processed.",
        }
        try:
            r = notifications.post("/api/notifications", json=payload)
            r.raise_for_status()
            order.notification_id = r.json()["id"]
            order.status = "PROCESSED"
        except httpx.HTTPError as exc:
            order.status = "FAILED"
            log.error("notification failed", extra={"order_id": order.id, "error": str(exc)})
        order.processed_at = datetime.now(UTC)
        session.commit()
        session.refresh(order)
        return order

    @app.post(prefix + "/{order_id}/process", response_model=OrderOut, dependencies=write_auth)
    def process_order(order_id: int, session: Session = Depends(db.session)):
        order = session.get(Order, order_id)
        if not order:
            raise HTTPException(status_code=404, detail="order not found")
        return process(order, session)

    @app.post(prefix + "/process-pending", dependencies=write_auth)
    def process_pending(limit: int = 10, session: Session = Depends(db.session)) -> dict:
        """Batch endpoint used by the Airflow order_processing_pipeline DAG."""
        pending = session.scalars(select(Order).where(Order.status == "PENDING").order_by(Order.id).limit(min(limit, 100))).all()
        results = [process(o, session) for o in pending]
        return {
            "processed": [o.id for o in results if o.status == "PROCESSED"],
            "failed": [o.id for o in results if o.status == "FAILED"],
            "notifications": [o.notification_id for o in results if o.notification_id],
        }

    if settings.shared_storage_enabled:
        router, storage = shared_storage_router(settings, keys)
        app.include_router(router)
        checks["shared_storage"] = lambda: storage.own_dir().stat()

    app.state.db = db
    return app
