#!/usr/bin/env bash
# Automated checks for the local k3s deployment (application + GitOps).
#   local/test.sh            # BASE=http://app.localtest.me by default
set -uo pipefail
BASE="${BASE:-http://app.localtest.me}"
pass=0; fail=0; skip=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
nope() { echo "  SKIP  $*"; skip=$((skip+1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
section() { printf '\n== %s\n' "$*"; }
KEY=$(kubectl -n apps get secret internal-api-key -o jsonpath='{.data.internal-api-key}' | base64 -d)
H=(-H "X-API-Key: $KEY" -H "Content-Type: application/json")
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

section "1. Platform"
for s in frontend user-service product-service order-service notification-service; do
  check "$s deployment ready" bash -c "[ \"\$(kubectl -n apps get deploy $s -o jsonpath='{.status.readyReplicas}')\" -ge 1 ]"
done
check "PostgreSQL ready" kubectl -n data rollout status deploy/postgres --timeout=10s
check "Redis ready" kubectl -n data rollout status deploy/redis --timeout=10s
check "db-bootstrap completed" bash -c "kubectl -n data get job db-bootstrap -o jsonpath='{.status.succeeded}' | grep -q 1"

section "2. Ingress and routing (single entry point)"
check "frontend at /" bash -c "curl -fsS $BASE/ | grep -q 'AKS POC Shop'"
for api in users products orders notifications; do
  check "GET /api/$api -> 200" curl -fsS -o /dev/null "$BASE/api/$api"
done
check "seed users from migration 002" bash -c "curl -fsS $BASE/api/users | grep -q ada.lovelace@example.com"

section "3. Security behaviour"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/users" -H 'Content-Type: application/json' -d '{"email":"x@example.com","full_name":"x"}')
[ "$code" = 401 ] && ok "write without API key rejected (401)" || bad "write without API key returned $code"
check "security headers present" bash -c "curl -fsS -D - -o /dev/null $BASE/api/users | grep -qi x-content-type-options"

section "4. PostgreSQL CRUD (user-service)"
email="local-$(date +%s)@example.com"
uid=$(curl -fsS "${H[@]}" -X POST "$BASE/api/users" -d "{\"email\":\"$email\",\"full_name\":\"Local Test\"}" | json 'd["id"]') && ok "create user $uid" || bad "create user"
check "update user" bash -c "curl -fsS -X PUT $BASE/api/users/$uid -H 'X-API-Key: $KEY' -H 'Content-Type: application/json' -d '{\"full_name\":\"Local Updated\"}' | grep -q 'Local Updated'"

section "5. Redis cache (product-service)"
pid=$(curl -fsS "$BASE/api/products" | json 'd[0]["id"]')
curl -fsS "${H[@]}" -X PUT "$BASE/api/products/$pid" -d '{"description":"cache test"}' -o /dev/null
c1=$(curl -fsS -D - -o /dev/null "$BASE/api/products/$pid" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache"{print $2}')
c2=$(curl -fsS -D - -o /dev/null "$BASE/api/products/$pid" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache"{print $2}')
[ "$c1/$c2" = "MISS/HIT" ] && ok "cache MISS then HIT, invalidated on update" || bad "cache headers were $c1/$c2"
check "Redis policy noeviction" bash -c "kubectl -n data exec deploy/redis -- redis-cli config get maxmemory-policy | grep -q noeviction"
check "cache keys namespaced and expiring" bash -c "k=\$(kubectl -n data exec deploy/redis -- redis-cli --scan --pattern 'app:product-service:item:*' | head -1); [ -n \"\$k\" ] && [ \"\$(kubectl -n data exec deploy/redis -- redis-cli ttl \"\$k\")\" -gt 0 ]"

section "6. Order flow across services + notification on shared storage"
oid=$(curl -fsS "${H[@]}" -X POST "$BASE/api/orders" -d "{\"user_id\":1,\"items\":[{\"product_id\":$pid,\"quantity\":1}]}" | json 'd["id"]') && ok "order $oid created (user + product services called)" || bad "create order"
nid=$(curl -fsS "${H[@]}" -X POST "$BASE/api/orders/$oid/process" | json 'd["notification_id"] or ""')
[ -n "$nid" ] && ok "order processed, notification $nid" || bad "order processing"
check "notification readable via API" curl -fsS -o /dev/null "$BASE/api/notifications/$nid"
check "frontend shows notification read from the shared volume" bash -c "curl -fsS $BASE/ | grep -q 'written by notification-service'"
f=$(kubectl -n apps exec deploy/frontend -- python -c "import glob;print(sorted(glob.glob('/mnt/shared/notification-service/outbox/*/*/*/$nid.json'))[0])" 2>/dev/null)
[ -n "$f" ] && ok "frontend pod reads the file written by notification-service: $f" || bad "shared file not visible to frontend"

section "7. Persistence after restarts"
kubectl -n apps rollout restart deploy/notification-service deploy/frontend >/dev/null
kubectl -n apps rollout status deploy/notification-service --timeout=120s >/dev/null
kubectl -n apps rollout status deploy/frontend --timeout=120s >/dev/null
check "notification file survives pod restarts" curl -fsS -o /dev/null "$BASE/api/notifications/$nid"
check "order survives restarts (PostgreSQL)" bash -c "curl -fsS $BASE/api/orders/$oid | grep -q PROCESSED"

section "8. Database isolation"
upw=$(kubectl -n data get secret db-passwords -o jsonpath='{.data.user-service}' | base64 -d)
if kubectl -n data exec deploy/postgres -- env PGPASSWORD="$upw" psql -h 127.0.0.1 -U user-service -d orders_db -c 'select 1' >/dev/null 2>&1; then
  bad "user-service could connect to orders_db"
else ok "user-service cannot connect to orders_db"; fi

section "9. NetworkPolicy (k3s enforces it)"
kubectl -n apps delete pod np-intruder --ignore-not-found --wait=true >/dev/null 2>&1
img=$(kubectl -n apps get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}')
kubectl -n apps run np-intruder --image="$img" --restart=Never --labels=app.kubernetes.io/name=intruder \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"np-intruder","image":"'"$img"'","command":["python","-c","import time;time.sleep(300)"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' >/dev/null 2>&1
kubectl -n apps wait --for=condition=Ready pod/np-intruder --timeout=60s >/dev/null 2>&1
if kubectl -n apps exec np-intruder -- python -c "import urllib.request;urllib.request.urlopen('http://notification-service:8000/healthz/live',timeout=5)" >/dev/null 2>&1; then
  bad "unlisted pod reached notification-service"
else ok "unlisted pod blocked from notification-service"; fi
kubectl -n apps delete pod np-intruder --ignore-not-found --wait=false >/dev/null 2>&1

section "10. GitOps (Argo CD)"
if kubectl get ns argocd >/dev/null 2>&1; then
  kubectl -n argocd get applications -o custom-columns=APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
  check "all applications Synced" bash -c "! kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.status.sync.status}{\"\n\"}{end}' | grep -v Synced"
  want=$(kubectl -n apps get deploy user-service -o jsonpath='{.spec.replicas}')
  kubectl -n apps scale deploy/user-service --replicas=$((want+2)) >/dev/null
  reverted=0
  for i in $(seq 1 30); do sleep 5; [ "$(kubectl -n apps get deploy user-service -o jsonpath='{.spec.replicas}')" = "$want" ] && { reverted=1; break; }; done
  [ "$reverted" = 1 ] && ok "manual drift reverted by Argo CD self-heal (~$((i*5)) s)" || bad "drift not reverted in 150 s"
else nope "Argo CD not installed (MODE=helm)"; fi

section "11. Airflow (optional)"
if kubectl -n airflow get deploy airflow-scheduler >/dev/null 2>&1; then
  sch="kubectl -n airflow exec deploy/airflow-scheduler -c scheduler --"
  check "DAGs synced from GitHub (Git-Sync)" bash -c "$sch airflow dags list 2>/dev/null | grep -q order_processing_pipeline"
  $sch airflow dags unpause order_processing_pipeline >/dev/null 2>&1
  run=$($sch airflow dags trigger order_processing_pipeline -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["dag_run_id"])' 2>/dev/null)
  state=""
  for i in $(seq 1 60); do sleep 10; state=$($sch airflow dags list-runs order_processing_pipeline -o json 2>/dev/null | python3 -c "import sys,json;print(next((r['state'] for r in json.load(sys.stdin) if r['run_id']=='$run'),''))" 2>/dev/null); [ "$state" = success ] || [ "$state" = failed ] && break; done
  [ "$state" = success ] && ok "order_processing_pipeline run succeeded (CeleryExecutor + Redis)" || bad "DAG run state: ${state:-unknown}"
else nope "Airflow not installed (WITH_AIRFLOW=1 local/up.sh)"; fi

printf '\nResult: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
