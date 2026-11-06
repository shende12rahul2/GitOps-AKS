"""Cross-service Azure Files check: every service writes and reads back a
marker on the shared volume, then one service reads a file another wrote."""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.sdk import dag, task

from aks_poc.services import SERVICES, call

ALL = ["frontend", *SERVICES]
PREFIX = {"frontend": "/frontend", **SERVICES}


@dag(
    dag_id="shared_storage_check",
    description="Verify the Azure Files RWX volume from every service",
    schedule="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args={"owner": "platform-team", "retries": 1, "retry_delay": timedelta(seconds=30)},
    tags=["aks-poc", "storage"],
)
def shared_storage_check():
    @task
    def selftest(service: str) -> dict:
        result = call(service, "GET", f"{PREFIX[service]}/shared/selftest")
        if not result["consistent"]:
            raise RuntimeError(f"{service}: read-back mismatch")
        return {"service": service, "node": result["read_back"]["node"]}

    @task
    def cross_service(results: list[dict]) -> str:
        from airflow.sdk import get_current_context

        run_id = get_current_context()["run_id"]
        marker = "airflow-" + "".join(c if c.isalnum() else "-" for c in run_id)
        # user-service writes to common/, order-service (possibly on another node) reads it back.
        call("user-service", "PUT", f"/api/users/shared/files/common/{marker}.txt", {"run_id": run_id}, authenticated=True)
        call("order-service", "GET", f"/api/orders/shared/files/common/{marker}.txt", authenticated=True)
        return f"{len(results)} services OK on nodes {sorted({r['node'] for r in results})}"

    cross_service(selftest.expand(service=ALL))


shared_storage_check()
