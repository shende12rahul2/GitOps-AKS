"""DAG validation run in CI (validate-dags.yml) before a DAG can be merged."""

import time
from pathlib import Path

import pytest
from airflow.models.dagbag import DagBag

DAGS = Path(__file__).resolve().parents[1] / "dags"


@pytest.fixture(scope="module")
def dagbag():
    start = time.monotonic()
    bag = DagBag(dag_folder=str(DAGS), include_examples=False)
    bag.parse_seconds = time.monotonic() - start
    return bag


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}, dagbag.import_errors


def test_expected_dags_present(dagbag):
    assert {"order_processing_pipeline", "shared_storage_check", "dag_sync_canary"} <= set(dagbag.dag_ids)


@pytest.mark.parametrize("dag_id", ["order_processing_pipeline", "shared_storage_check", "dag_sync_canary"])
def test_dag_policies(dagbag, dag_id):
    dag = dagbag.dags[dag_id]
    assert dag.catchup is False, "catchup must be disabled"
    assert dag.tags and "aks-poc" in dag.tags
    assert dag.description
    for t in dag.tasks:
        assert t.owner not in ("airflow", None, ""), f"{t.task_id}: set an owner"


def test_parsing_is_fast(dagbag):
    # Heavy top-level code slows every DAG processor loop.
    assert dagbag.parse_seconds < 10


def test_pipeline_shape(dagbag):
    dag = dagbag.dags["order_processing_pipeline"]
    assert dag.get_task("verify_notifications").upstream_task_ids == {"process_pending_orders"}
    assert dag.get_task("create_test_orders").upstream_task_ids == {"fetch_users", "query_products"}
