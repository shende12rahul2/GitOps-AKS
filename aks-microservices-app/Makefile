# Developer entry points. Python 3.13, run from the repository root.
SERVICES := frontend user-service product-service order-service notification-service
PY ?= python3

.PHONY: venv lint format test test-airflow up down integration

venv:
	$(PY) -m venv .venv && . .venv/bin/activate && pip install -e libs/svc-common -r services/frontend/requirements.txt -r tools/db-bootstrap/requirements.txt pytest fakeredis ruff

lint:
	ruff check . && ruff format --check .

format:
	ruff format . && ruff check --fix .

test:
	cd libs/svc-common && python -m pytest -q tests
	for s in $(SERVICES); do (cd services/$$s && REDIS_ENABLED=false python -m pytest -q tests) || exit 1; done
	cd tools/db-bootstrap && python -m pytest -q tests

test-airflow:
	cd airflow && AIRFLOW_HOME=/tmp/airflow python -m pytest -q tests

up:
	docker compose up --build -d

down:
	docker compose down -v

integration:
	cd services/user-service && INTEGRATION_BASE_URL=http://localhost:8001 INTERNAL_API_KEY=local-dev-key python -m pytest -q tests/integration
	cd services/product-service && INTEGRATION_BASE_URL=http://localhost:8002 INTERNAL_API_KEY=local-dev-key python -m pytest -q tests/integration
	cd services/order-service && INTEGRATION_BASE_URL=http://localhost:8003 INTERNAL_API_KEY=local-dev-key python -m pytest -q tests/integration
	cd services/notification-service && INTEGRATION_BASE_URL=http://localhost:8004 INTERNAL_API_KEY=local-dev-key python -m pytest -q tests/integration
