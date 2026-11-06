"""Product Service: PostgreSQL (products_db) with an Azure Managed Redis cache.

Caching strategy (cache-aside):
  * item:<id>          TTL ITEM_TTL   - deleted on update/reserve/release
  * list:v<version>    TTL LIST_TTL   - invalidated by bumping list:version, so
                                        stale list pages simply stop being read
  * stats:hits/misses  counters for the demo endpoint
Responses carry X-Cache: HIT | MISS | BYPASS.
"""

from __future__ import annotations

from datetime import datetime

from fastapi import Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from svc_common.app import create_app, shared_storage_router
from svc_common.auth import require_api_key
from svc_common.cache import Cache, build_client
from svc_common.config import CommonSettings
from svc_common.db import Database

from .models import Product


class Settings(CommonSettings):
    service_name: str = "product-service"
    redis_enabled: bool = True
    redis_key_prefix: str = "app:product-service"
    cache_item_ttl_seconds: int = 60
    cache_list_ttl_seconds: int = 30


class ProductIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    description: str = ""
    price_cents: int = Field(ge=0)
    stock: int = Field(ge=0, default=0)


class ProductUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = None
    price_cents: int | None = Field(default=None, ge=0)
    stock: int | None = Field(default=None, ge=0)


class ProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    sku: str
    name: str
    description: str
    price_cents: int
    stock: int
    updated_at: datetime | None = None


class Quantity(BaseModel):
    quantity: int = Field(gt=0, le=1000)


def build(settings: Settings | None = None, redis_client=None):
    settings = settings or Settings()
    db = Database(settings)
    client = redis_client if redis_client is not None else (build_client(settings) if settings.redis_enabled else None)
    cache = Cache(client, settings.redis_key_prefix)
    checks = {"postgres": db.ping}
    if cache.enabled:
        checks["redis"] = cache.ping
    app, keys = create_app(settings, "Product Service", readiness=checks)
    write_auth = [Depends(require_api_key(keys))]
    prefix = settings.api_prefix

    def serialize(p: Product) -> dict:
        return ProductOut.model_validate(p).model_dump(mode="json")

    def invalidate(product_id: int | None = None) -> None:
        if product_id is not None:
            cache.delete(f"item:{product_id}")
        cache.incr("list:version")

    def mark(response: Response, hit: bool | None) -> None:
        response.headers["X-Cache"] = "BYPASS" if hit is None else ("HIT" if hit else "MISS")
        if hit is not None:
            cache.incr("stats:hits" if hit else "stats:misses")

    @app.get(prefix, response_model=list[ProductOut])
    def list_products(response: Response, session: Session = Depends(db.session)):
        key = f"list:v{cache.get_int('list:version')}"
        if (cached := cache.get_json(key)) is not None:
            mark(response, True)
            return cached
        items = [serialize(p) for p in session.scalars(select(Product).order_by(Product.id))]
        cache.set_json(key, items, settings.cache_list_ttl_seconds)
        mark(response, False if cache.enabled else None)
        return items

    @app.get(prefix + "/cache/stats")
    def cache_stats() -> dict:
        hits, misses = cache.get_int("stats:hits"), cache.get_int("stats:misses")
        total = hits + misses
        return {
            "enabled": cache.enabled,
            "hits": hits,
            "misses": misses,
            "hit_ratio": round(hits / total, 3) if total else None,
            "item_ttl_seconds": settings.cache_item_ttl_seconds,
            "list_ttl_seconds": settings.cache_list_ttl_seconds,
            "key_prefix": settings.redis_key_prefix,
        }

    @app.get(prefix + "/{product_id}", response_model=ProductOut)
    def get_product(product_id: int, response: Response, session: Session = Depends(db.session)):
        if (cached := cache.get_json(f"item:{product_id}")) is not None:
            mark(response, True)
            return cached
        product = session.get(Product, product_id)
        if not product:
            raise HTTPException(status_code=404, detail="product not found")
        data = serialize(product)
        cache.set_json(f"item:{product_id}", data, settings.cache_item_ttl_seconds)
        mark(response, False if cache.enabled else None)
        return data

    @app.post(prefix, response_model=ProductOut, status_code=status.HTTP_201_CREATED, dependencies=write_auth)
    def create_product(body: ProductIn, session: Session = Depends(db.session)):
        product = Product(**body.model_dump())
        session.add(product)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(status_code=409, detail="sku already exists") from exc
        session.refresh(product)
        invalidate()
        return product

    @app.put(prefix + "/{product_id}", response_model=ProductOut, dependencies=write_auth)
    def update_product(product_id: int, body: ProductUpdate, session: Session = Depends(db.session)):
        product = session.get(Product, product_id)
        if not product:
            raise HTTPException(status_code=404, detail="product not found")
        for field, value in body.model_dump(exclude_none=True).items():
            setattr(product, field, value)
        session.commit()
        session.refresh(product)
        invalidate(product_id)
        return product

    @app.post(prefix + "/{product_id}/reserve", response_model=ProductOut, dependencies=write_auth)
    def reserve(product_id: int, body: Quantity, session: Session = Depends(db.session)):
        # Single conditional UPDATE: no oversell even with concurrent replicas.
        result = session.execute(
            update(Product).where(Product.id == product_id, Product.stock >= body.quantity).values(stock=Product.stock - body.quantity)
        )
        if result.rowcount == 0:
            session.rollback()
            if session.get(Product, product_id) is None:
                raise HTTPException(status_code=404, detail="product not found")
            raise HTTPException(status_code=409, detail="insufficient stock")
        session.commit()
        invalidate(product_id)
        return session.get(Product, product_id)

    @app.post(prefix + "/{product_id}/release", response_model=ProductOut, dependencies=write_auth)
    def release(product_id: int, body: Quantity, session: Session = Depends(db.session)):
        result = session.execute(update(Product).where(Product.id == product_id).values(stock=Product.stock + body.quantity))
        if result.rowcount == 0:
            session.rollback()
            raise HTTPException(status_code=404, detail="product not found")
        session.commit()
        invalidate(product_id)
        return session.get(Product, product_id)

    if settings.shared_storage_enabled:
        router, storage = shared_storage_router(settings, keys)
        app.include_router(router)
        checks["shared_storage"] = lambda: storage.own_dir().stat()

    app.state.db = db
    app.state.cache = cache
    return app
