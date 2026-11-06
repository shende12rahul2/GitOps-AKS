"""Notification Service: renders notifications as JSON files on Azure Files.

Files: /mnt/shared/notification-service/outbox/YYYY/MM/DD/<uuid>.json
Each file is written atomically (temp file + rename), so the frontend and
Airflow, running on other nodes, never read a partial notification. A daily
summary in common/ is updated under a cross-node lock file.
"""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from typing import Literal

from fastapi import Depends, HTTPException, status
from pydantic import BaseModel, Field

from svc_common.app import create_app, shared_storage_router
from svc_common.auth import require_api_key
from svc_common.config import CommonSettings
from svc_common.shared_storage import SharedStorage


class Settings(CommonSettings):
    service_name: str = "notification-service"
    db_enabled: bool = False
    shared_storage_enabled: bool = True


class NotificationIn(BaseModel):
    order_id: int | None = None
    user_id: int | None = None
    channel: Literal["email", "sms", "file"] = "email"
    recipient: str | None = Field(default=None, max_length=320)
    subject: str = Field(min_length=1, max_length=200)
    message: str = Field(min_length=1, max_length=5000)


def build(settings: Settings | None = None):
    settings = settings or Settings()
    storage = SharedStorage(settings.shared_mount_path, settings.service_name)
    checks = {"shared_storage": lambda: storage.own_dir().stat()}
    app, keys = create_app(settings, "Notification Service", readiness=checks)
    auth = [Depends(require_api_key(keys))]
    prefix = settings.api_prefix

    @app.post(prefix, status_code=status.HTTP_201_CREATED, dependencies=auth)
    def create_notification(body: NotificationIn) -> dict:
        now = datetime.now(UTC)
        nid = uuid.uuid4().hex
        record = {
            "id": nid,
            "created_at": now.isoformat(),
            "written_by": {"pod": settings.pod_name, "node": settings.node_name},
            **body.model_dump(),
        }
        rel = f"outbox/{now:%Y/%m/%d}/{nid}.json"
        storage.write_json(rel, record)
        # Daily counter shared across replicas/nodes: read-modify-write under a lock file.
        with storage.exclusive_lock(f"summary-{now:%Y%m%d}"):
            name = f"notification-summary-{now:%Y%m%d}.json"
            try:
                summary = json.loads(storage.read_text("common", name))
            except FileNotFoundError:
                summary = {"date": f"{now:%Y-%m-%d}", "count": 0}
            summary["count"] += 1
            summary["last_id"] = nid
            storage.write_json(name, summary, area="common")
        return {**record, "path": f"{settings.service_name}/{rel}"}

    @app.get(prefix)
    def list_notifications(limit: int = 20) -> dict:
        files = storage.list_files(settings.service_name, "outbox", limit=min(limit, 200))
        items = []
        for f in files:
            try:
                items.append(json.loads(storage.read_text(settings.service_name, f["path"])))
            except (FileNotFoundError, json.JSONDecodeError):
                continue
        return {"count": len(items), "items": items}

    @app.get(prefix + "/summary/today")
    def today() -> dict:
        name = f"notification-summary-{datetime.now(UTC):%Y%m%d}.json"
        try:
            return json.loads(storage.read_text("common", name))
        except FileNotFoundError:
            return {"date": f"{datetime.now(UTC):%Y-%m-%d}", "count": 0}

    @app.get(prefix + "/{notification_id}")
    def get_notification(notification_id: str) -> dict:
        if not notification_id.isalnum():
            raise HTTPException(status_code=400, detail="invalid id")
        for f in storage.list_files(settings.service_name, "outbox", limit=10_000):
            if f["path"].endswith(f"{notification_id}.json"):
                return json.loads(storage.read_text(settings.service_name, f["path"]))
        raise HTTPException(status_code=404, detail="notification not found")

    router, _ = shared_storage_router(settings, keys)
    app.include_router(router)
    app.state.storage = storage
    return app
