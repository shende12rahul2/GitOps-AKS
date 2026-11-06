"""Order processing pipeline: exercises every microservice end to end.

check_health (mapped) -> fetch_users, query_products -> create_test_orders
-> process_pending_orders -> verify_notifications

Owner: application team. Changes arrive through pull requests to
aks-microservices-app (validated by validate-dags.yml) and Git-Sync.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.sdk import dag, task

from aks_poc.services import SERVICES, call

DEFAULT_ARGS = {
    "owner": "app-team",
    "retries": 2,
    "retry_delay": timedelta(seconds=30),
    "execution_timeout": timedelta(minutes=5),
}


@dag(
    dag_id="order_processing_pipeline",
    description="Create test orders, process them and verify notification output",
    schedule="0 * * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["aks-poc", "orders", "microservices"],
)
def order_processing_pipeline():
    @task
    def check_health(service: str) -> str:
        call(service, "GET", "/healthz/ready")
        return service

    @task
    def fetch_users() -> list[int]:
        users = call("user-service", "GET", "/api/users")
        if not users:
            raise ValueError("user-service returned no users")
        return [u["id"] for u in users]

    @task
    def query_products() -> list[dict]:
        products = call("product-service", "GET", "/api/products")
        in_stock = [{"id": p["id"], "price_cents": p["price_cents"]} for p in products if p["stock"] > 0]
        if not in_stock:
            raise ValueError("no products in stock")
        return in_stock

    @task
    def create_test_orders(user_ids: list[int], products: list[dict], count: int = 2) -> list[int]:
        created = []
        for i in range(count):
            body = {"user_id": user_ids[i % len(user_ids)], "items": [{"product_id": products[i % len(products)]["id"], "quantity": 1}]}
            created.append(call("order-service", "POST", "/api/orders", body, authenticated=True)["id"])
        return created

    @task
    def process_pending_orders(order_ids: list[int]) -> list[str]:
        result = call("order-service", "POST", "/api/orders/process-pending?limit=50", authenticated=True)
        missing = set(order_ids) - set(result["processed"])
        if missing:
            raise RuntimeError(f"orders not processed: {sorted(missing)} (failed: {result['failed']})")
        return result["notifications"]

    @task
    def verify_notifications(notification_ids: list[str]) -> int:
        for nid in notification_ids:
            record = call("notification-service", "GET", f"/api/notifications/{nid}")
            if record["id"] != nid:
                raise RuntimeError(f"notification {nid} not found on the shared volume")
        return len(notification_ids)

    healthy = check_health.expand(service=list(SERVICES))
    users, products = fetch_users(), query_products()
    healthy >> [users, products]
    verify_notifications(process_pending_orders(create_test_orders(users, products)))


order_processing_pipeline()
