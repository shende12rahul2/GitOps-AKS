"""User Service: CRUD for sample users in PostgreSQL (users_db)."""

from __future__ import annotations

from datetime import datetime

from fastapi import Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from svc_common.app import create_app, shared_storage_router
from svc_common.auth import require_api_key
from svc_common.config import CommonSettings
from svc_common.db import Database

from .models import User


class Settings(CommonSettings):
    service_name: str = "user-service"


class UserIn(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=1, max_length=200)


class UserUpdate(BaseModel):
    email: EmailStr | None = None
    full_name: str | None = Field(default=None, min_length=1, max_length=200)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    email: str
    full_name: str
    created_at: datetime | None = None
    updated_at: datetime | None = None


def build(settings: Settings | None = None):
    settings = settings or Settings()
    db = Database(settings)
    checks = {"postgres": db.ping}
    app, keys = create_app(settings, "User Service", readiness=checks)
    write_auth = [Depends(require_api_key(keys))]
    prefix = settings.api_prefix

    @app.get(prefix, response_model=list[UserOut])
    def list_users(limit: int = 100, session: Session = Depends(db.session)):
        return session.scalars(select(User).order_by(User.id).limit(min(limit, 500))).all()

    @app.get(prefix + "/{user_id}", response_model=UserOut)
    def get_user(user_id: int, session: Session = Depends(db.session)):
        user = session.get(User, user_id)
        if not user:
            raise HTTPException(status_code=404, detail="user not found")
        return user

    @app.post(prefix, response_model=UserOut, status_code=status.HTTP_201_CREATED, dependencies=write_auth)
    def create_user(body: UserIn, session: Session = Depends(db.session)):
        user = User(email=body.email.lower(), full_name=body.full_name)
        session.add(user)
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(status_code=409, detail="email already exists") from exc
        session.refresh(user)
        return user

    @app.put(prefix + "/{user_id}", response_model=UserOut, dependencies=write_auth)
    def update_user(user_id: int, body: UserUpdate, session: Session = Depends(db.session)):
        user = session.get(User, user_id)
        if not user:
            raise HTTPException(status_code=404, detail="user not found")
        if body.email is not None:
            user.email = body.email.lower()
        if body.full_name is not None:
            user.full_name = body.full_name
        try:
            session.commit()
        except IntegrityError as exc:
            session.rollback()
            raise HTTPException(status_code=409, detail="email already exists") from exc
        session.refresh(user)
        return user

    if settings.shared_storage_enabled:
        router, storage = shared_storage_router(settings, keys)
        app.include_router(router)
        checks["shared_storage"] = lambda: storage.own_dir().stat()

    app.state.db = db
    return app
