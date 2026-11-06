"""FastAPI application factory shared by all services."""

from __future__ import annotations

import json
import logging
import time
import uuid
from collections.abc import Callable
from pathlib import Path

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse, PlainTextResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from .auth import ApiKeyStore, require_api_key
from .config import CommonSettings
from .logging import Timer, configure_logging, request_id_var
from .shared_storage import SharedStorage, StorageError

log = logging.getLogger("http")

REQUESTS = Counter("http_requests_total", "HTTP requests", ["service", "method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP latency", ["service", "method", "route"])

ReadinessCheck = Callable[[], None]


def create_app(settings: CommonSettings, title: str, readiness: dict[str, ReadinessCheck] | None = None) -> tuple[FastAPI, ApiKeyStore]:
    configure_logging(settings.service_name, settings.environment, settings.log_level, settings.pod_name, settings.node_name)
    app = FastAPI(
        title=title, version=settings.version, docs_url=f"{settings.api_prefix}/docs", openapi_url=f"{settings.api_prefix}/openapi.json"
    )
    keys = ApiKeyStore(settings)
    checks = readiness or {}

    @app.middleware("http")
    async def observability(request: Request, call_next):
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex
        token = request_id_var.set(rid)
        start = time.perf_counter()
        status = 500
        try:
            response: Response = await call_next(request)
            status = response.status_code
        finally:
            route = getattr(request.scope.get("route"), "path", request.url.path)
            elapsed = time.perf_counter() - start
            REQUESTS.labels(settings.service_name, request.method, route, str(status)).inc()
            LATENCY.labels(settings.service_name, request.method, route).observe(elapsed)
            if not route.startswith("/healthz") and route != "/metrics":
                log.info(
                    "request",
                    extra={"method": request.method, "path": request.url.path, "status": status, "duration_ms": round(elapsed * 1000, 2)},
                )
            request_id_var.reset(token)
        response.headers["X-Request-ID"] = rid
        # Security headers (also applied behind AGIC/Traefik, so they hold in every ingress mode).
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        if settings.hsts_enabled:
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        return response

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        log.exception("unhandled error")
        return JSONResponse(status_code=500, content={"detail": "internal error", "request_id": request_id_var.get()})

    @app.get("/healthz/live", include_in_schema=False)
    def live() -> dict:
        return {"status": "ok"}

    @app.get("/healthz/ready", include_in_schema=False)
    def ready() -> JSONResponse:
        results, ok = {}, True
        for name, check in checks.items():
            with Timer() as t:
                try:
                    check()
                    results[name] = {"status": "ok"}
                except Exception as exc:  # noqa: BLE001 - report any dependency failure
                    ok = False
                    results[name] = {"status": "error", "error": type(exc).__name__}
            results[name]["ms"] = t.ms
        return JSONResponse(status_code=200 if ok else 503, content={"status": "ok" if ok else "degraded", "checks": results})

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> PlainTextResponse:
        return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.get(f"{settings.api_prefix}/info")
    def info() -> dict:
        return {
            "service": settings.service_name,
            "version": settings.version,
            "environment": settings.environment,
            "pod": settings.pod_name,
            "node": settings.node_name,
        }

    return app, keys


def shared_storage_router(settings: CommonSettings, keys: ApiKeyStore) -> tuple[APIRouter, SharedStorage]:
    """Endpoints used by the cross-node Azure Files validation (docs/validation.md)."""
    storage = SharedStorage(settings.shared_mount_path, settings.service_name)
    try:
        # Idempotent (mkdir -p) and safe when several pods start at once on different nodes.
        storage.ensure_layout()
    except OSError as exc:
        log.warning("shared storage layout not created", extra={"error": str(exc)})
    router = APIRouter(prefix=f"{settings.api_prefix}/shared", tags=["shared-storage"])
    auth = Depends(require_api_key(keys))

    @router.get("/selftest")
    def selftest() -> dict:
        marker = f"selftest/{settings.pod_name}.json"
        payload = {"pod": settings.pod_name, "node": settings.node_name, "at": time.time()}
        storage.write_json(marker, payload)
        read_back = json.loads(storage.read_text(settings.service_name, marker))
        return {"wrote": marker, "read_back": read_back, "consistent": read_back == payload, "mount": settings.shared_mount_path}

    @router.put("/files/{area}/{name}", dependencies=[auth])
    async def write_file(area: str, name: str, request: Request) -> dict:
        body = await request.body()
        try:
            path = storage.write_bytes(name, body, area=area)
        except StorageError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc
        return {
            "written": str(Path(path).relative_to(storage.root)),
            "bytes": len(body),
            "node": settings.node_name,
            "pod": settings.pod_name,
        }

    @router.get("/files/{owner}/{name:path}", dependencies=[auth])
    def read_file(owner: str, name: str) -> PlainTextResponse:
        try:
            return PlainTextResponse(storage.read_text(owner, name), headers={"X-Served-By-Node": settings.node_name})
        except FileNotFoundError as exc:
            raise HTTPException(status_code=404, detail="not found") from exc
        except StorageError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc

    @router.get("/files/{owner}", dependencies=[auth])
    def list_files(owner: str, limit: int = 50) -> dict:
        try:
            return {"owner": owner, "files": storage.list_files(owner, limit=limit)}
        except StorageError as exc:
            raise HTTPException(status_code=403, detail=str(exc)) from exc

    return router, storage
