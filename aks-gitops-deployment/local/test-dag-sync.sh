#!/usr/bin/env bash
# Git-Sync -> Airflow DAG sync test.
#
# Proves that DAGs in GitHub (aks-microservices-app/airflow/dags) reach Airflow
# through Git-Sync, and optionally that a pushed change (and its revert) shows up
# in Airflow without any redeploy.
#
# Checks:
#   1. The synced DAG folder contains the DAG files from Git.
#   2. Airflow has parsed and registered every expected DAG, with no import errors.
#   3. (BUMP=1) Bump DAG_VERSION in dag_sync_canary.py, commit, push, and wait
#      until Airflow shows the new version; then revert, push, and wait for the
#      old version again. Prints how long each change took to arrive.
#
# Where Airflow runs (TARGET):
#   k8s  (default) Airflow from `WITH_AIRFLOW=1 ./up.sh`; the dag-processor pod
#                  has the git-sync sidecar. Uses kubectl exec.
#   host           Airflow CLI on this machine (git-sync + `airflow dag-processor`
#                  started by hand, see LOCAL-SETUP-AND-TESTING.md). The
#                  AIRFLOW_* environment variables must already be exported.
#
# Options (environment variables):
#   BUMP=1            run the push/revert test (needs push rights on REVISION).
#   REVISION          branch Git-Sync follows (default: current branch).
#   TIMEOUT=300       seconds to wait for each change.
#   AIRFLOW_NS=airflow, AIRFLOW_DEPLOY=airflow-dag-processor, AIRFLOW_CONTAINER=dag-processor
set -euo pipefail

TARGET="${TARGET:-k8s}"
BUMP="${BUMP:-0}"
TIMEOUT="${TIMEOUT:-300}"
AIRFLOW_NS="${AIRFLOW_NS:-airflow}"
AIRFLOW_DEPLOY="${AIRFLOW_DEPLOY:-airflow-dag-processor}"
AIRFLOW_CONTAINER="${AIRFLOW_CONTAINER:-dag-processor}"
EXPECTED_DAGS=(order_processing_pipeline shared_storage_check dag_sync_canary)

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
CANARY_REL="$(cd "$ROOT" && git ls-files '*airflow/dags/dag_sync_canary.py' | head -1)"
[ -n "$CANARY_REL" ] || { echo "dag_sync_canary.py not found in $ROOT"; exit 2; }
REVISION="${REVISION:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)}"

pass=0; fail=0
ok()  { echo "  PASS  $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }

af_json() {  # airflow ... -o json, keeping only the JSON line (CLI also logs to stdout)
  af "$@" -o json 2>/dev/null | grep -E '^\s*[\[{]' | tail -1
}
af() {   # run an airflow CLI command where Airflow lives
  if [ "$TARGET" = k8s ]; then
    kubectl -n "$AIRFLOW_NS" exec "deploy/$AIRFLOW_DEPLOY" -c "$AIRFLOW_CONTAINER" -- airflow "$@"
  else
    airflow "$@"
  fi
}
in_af() {  # run a shell command where Airflow lives
  if [ "$TARGET" = k8s ]; then
    kubectl -n "$AIRFLOW_NS" exec "deploy/$AIRFLOW_DEPLOY" -c "$AIRFLOW_CONTAINER" -- sh -c "$1"
  else
    sh -c "$1"
  fi
}
canary_version() {  # version string Airflow currently has for the canary DAG
  af_json dags details dag_sync_canary | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
    d = d[0] if isinstance(d, list) else d
    m = re.search(r"v(\S+)$", d.get("description") or "")
    print(m.group(1) if m else "")
except Exception:
    print("")'
}
wait_for_version() {  # $1 = expected version; prints seconds taken
  local want="$1" start now
  start=$(date +%s)
  while :; do
    [ "$(canary_version)" = "$want" ] && { echo $(( $(date +%s) - start )); return 0; }
    now=$(date +%s)
    [ $((now - start)) -ge "$TIMEOUT" ] && return 1
    sleep 3
  done
}

echo "== Git-Sync -> Airflow DAG sync test (target=$TARGET, revision=$REVISION)"

echo "-- 1. DAG files synced from Git"
dags_folder="$(af config get-value core dags_folder 2>/dev/null | grep '^/' | tail -1)"
listing="$(in_af "ls -1 '$dags_folder'" 2>/dev/null || true)"
for f in order_processing_pipeline.py shared_storage_check.py dag_sync_canary.py; do
  grep -qx "$f" <<<"$listing" && ok "$f present in $dags_folder" || bad "$f missing from $dags_folder"
done
if [ "$TARGET" = k8s ]; then
  sha="$(kubectl -n "$AIRFLOW_NS" logs "deploy/$AIRFLOW_DEPLOY" -c git-sync --tail=200 2>/dev/null \
        | grep -o '"hash":"[0-9a-f]*"' | tail -1 | cut -d'"' -f4 || true)"
  [ -n "$sha" ] && echo "        git-sync is at commit ${sha:0:12}"
fi

echo "-- 2. DAGs registered in Airflow"
listed="$(af_json dags list | python3 -c 'import json,sys; [print(d["dag_id"]) for d in json.load(sys.stdin)]' 2>/dev/null || true)"
for d in "${EXPECTED_DAGS[@]}"; do
  grep -qx "$d" <<<"$listed" && ok "DAG $d registered" || bad "DAG $d not registered"
done
errors="$(af_json dags list-import-errors || true)"
if [ "$errors" = "[]" ] || [ -z "$errors" ]; then ok "no DAG import errors"; else bad "import errors: $errors"; fi
current="$(canary_version)"
[ -n "$current" ] && ok "dag_sync_canary at v$current" || bad "could not read dag_sync_canary version"

if [ "$BUMP" = 1 ] && [ -n "$current" ]; then
  echo "-- 3. Push a change and its revert through Git"
  [ -z "$(git -C "$ROOT" status --porcelain -- "$CANARY_REL")" ] || { bad "$CANARY_REL has local changes"; exit 1; }
  new="${current%.*}.$(( ${current##*.} + 1 ))"
  sed -i "s/^DAG_VERSION = \".*\"/DAG_VERSION = \"$new\"/" "$ROOT/$CANARY_REL"
  git -C "$ROOT" commit -q -m "test(airflow): bump dag_sync_canary to $new (Git-Sync test)" -- "$CANARY_REL"
  git -C "$ROOT" push -q origin "HEAD:$REVISION"
  echo "        pushed v$new, waiting for Airflow (timeout ${TIMEOUT}s)"
  if t=$(wait_for_version "$new"); then ok "Airflow picked up v$new in ${t}s"; else bad "v$new not seen after ${TIMEOUT}s"; fi

  git -C "$ROOT" revert --no-edit HEAD >/dev/null
  git -C "$ROOT" push -q origin "HEAD:$REVISION"
  echo "        pushed revert to v$current, waiting for Airflow"
  if t=$(wait_for_version "$current"); then ok "Airflow rolled back to v$current in ${t}s"; else bad "rollback to v$current not seen after ${TIMEOUT}s"; fi
fi

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
