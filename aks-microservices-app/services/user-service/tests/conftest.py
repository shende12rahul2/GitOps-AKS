import pytest
from fastapi.testclient import TestClient

from app.main import Settings, build
from svc_common.db import Base

API_KEY = "test-key"


@pytest.fixture()
def client(tmp_path):
    settings = Settings(
        database_url="sqlite+pysqlite:///:memory:",
        internal_api_keys=API_KEY,
        internal_api_keys_file=None,
        shared_storage_enabled=True,
        shared_mount_path=str(tmp_path),
    )
    app = build(settings)
    Base.metadata.create_all(app.state.db.engine)
    (tmp_path / "user-service").mkdir(exist_ok=True)  # also created by the service at start-up
    return TestClient(app)


@pytest.fixture()
def auth():
    return {"X-API-Key": API_KEY}
