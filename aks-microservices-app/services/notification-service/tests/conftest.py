import pytest
from fastapi.testclient import TestClient

from app.main import Settings, build

API_KEY = "test-key"


@pytest.fixture()
def client(tmp_path):
    app = build(
        Settings(
            shared_mount_path=str(tmp_path), internal_api_keys=API_KEY, internal_api_keys_file=None, node_name="node-a", pod_name="notif-1"
        )
    )
    app.state.storage.ensure_layout()
    return TestClient(app)


@pytest.fixture()
def auth():
    return {"X-API-Key": API_KEY}
