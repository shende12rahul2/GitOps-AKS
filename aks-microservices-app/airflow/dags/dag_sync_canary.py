"""Git-Sync canary. Bump DAG_VERSION in a pull request; after merge the new
value appears in the Airflow UI (DAG description) within the sync period,
proving the GitHub -> Git-Sync -> DAG processor path end to end."""

from __future__ import annotations

from datetime import datetime

from airflow.sdk import dag, task

DAG_VERSION = "1.0.0"


@dag(
    dag_id="dag_sync_canary",
    description=f"Git-Sync canary v{DAG_VERSION}",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args={"owner": "platform-team", "retries": 0},
    tags=["aks-poc", "git-sync"],
)
def dag_sync_canary():
    @task
    def report_version() -> str:
        print(f"dag_sync_canary version {DAG_VERSION}")
        return DAG_VERSION

    report_version()


dag_sync_canary()
