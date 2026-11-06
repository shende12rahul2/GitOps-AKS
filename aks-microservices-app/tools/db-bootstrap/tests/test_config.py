from pathlib import Path

import pytest

from bootstrap import Config

LOCAL = Path(__file__).resolve().parents[1] / "local" / "bootstrap.yaml"


def test_local_config_loads():
    cfg = Config.load(str(LOCAL))
    assert {d.name for d in cfg.databases} == {"users_db", "products_db", "orders_db", "airflow_metadata"}
    assert cfg.principals["airflow"].type == "password"


def test_unknown_principal_rejected(tmp_path):
    p = tmp_path / "c.yaml"
    p.write_text("principals: {a: {role: a, type: local-login}}\ndatabases: [{name: x, owner: b}]\n")
    with pytest.raises(ValueError):
        Config.load(str(p))
