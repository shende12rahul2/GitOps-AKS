# Local setup and testing (k3s on a laptop)

This guide runs the **application and GitOps parts** of the AKS POC on a laptop
with k3s, and tests them. You don't need an Azure subscription. The Azure
infrastructure (Terraform) is tested separately with `terraform test` in
`aks-infrastructure-iac`.

Everything lives in [`aks-gitops-deployment/local/`](aks-gitops-deployment/local/):

| File | Purpose |
|---|---|
| `up.sh` | Builds the 5 service images and imports them into k3s, creates the local secrets, then deploys everything (Argo CD or Helm mode). Airflow is optional. |
| `test.sh` | Automated end-to-end checks in 11 sections. |
| `test-dag-sync.sh` | Tests the GitHub → Git-Sync → Airflow DAG path. It can push a change and its revert, and times how long each takes to arrive. |
| `down.sh` | Removes everything `up.sh` created. |
| `infra/` | Local stand-ins for the Azure data services: PostgreSQL, Redis, shared storage, the DB bootstrap job and the Traefik ingress. |
| `values/` | Local overrides for the **same Helm charts** that AKS uses. |
| `argocd/` | Local Argo CD install, plus an Application and an ApplicationSet that sync from GitHub. |

---

## 1. What is tested locally vs only on Azure

| Area | Local (k3s) | Only on AKS |
|---|---|---|
| 5 microservices, Helm charts, probes, migrations | ✅ same charts and images | |
| Single entry point and path routing | ✅ Traefik Ingress (`app.localtest.me`) | App Gateway WAF_v2 + AGIC |
| PostgreSQL CRUD and per-service DB isolation | ✅ postgres:17 with per-service users | PostgreSQL Flexible with Entra auth |
| Redis cache-aside | ✅ redis:8 (`noeviction`) | Azure Managed Redis |
| Shared storage between services | ✅ local-path PVC | Azure Files with managed identity |
| NetworkPolicy (default deny + allow list) | ✅ enforced by k3s | Cilium |
| GitOps: Argo CD app-of-apps, auto-sync, self-heal, prune | ✅ syncs from your GitHub branch | |
| Airflow 3 (CeleryExecutor) and **DAG sync from Git (Git-Sync)** | ✅ official chart 1.22.0 | |
| Workload identity, Key Vault CSI, private cluster, WAF, Entra login | ❌ replaced by Kubernetes Secrets or password auth | ✅ |

---

## 2. Prerequisites

- Linux laptop (or WSL2) with 4 CPUs and 8 GB RAM free (**16 GB** with Airflow). Free disk: about 6 GB, or 10 GB with Airflow.
- k3s:
  ```bash
  curl -sfL https://get.k3s.io | sh -
  ```
  ```bash
  mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $USER ~/.kube/config
  ```
  k3d and Rancher Desktop also work, with `IMPORT=k3d` or `IMPORT=none`.
- `docker` or `buildah` (`BUILDER=buildah`, no daemon needed), plus `helm` 3, `kubectl`, `git`, `python3` and `curl`.
- The repository pushed to GitHub, because Argo CD and Git-Sync pull from it. For a private repository, set a fine-grained **read-only** token in your shell. It only goes into in-cluster Secrets and is never committed:
  ```bash
  export GITHUB_TOKEN=...
  ```

---

## 3. Bring it up

```bash
git clone https://github.com/<you>/GitOps-AKS.git && cd GitOps-AKS
git checkout <branch>        # the branch Argo CD and Git-Sync will follow
```

Choose one:

```bash
aks-gitops-deployment/local/up.sh                    # GitOps mode: Argo CD syncs the apps from GitHub
```

```bash
MODE=helm aks-gitops-deployment/local/up.sh          # no Argo CD: helm installs the same charts
```

```bash
WITH_AIRFLOW=1 aks-gitops-deployment/local/up.sh     # also Airflow 3.2.2 with Git-Sync
```

`up.sh` options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `MODE` | `argocd` | `argocd` (GitOps) or `helm` |
| `WITH_AIRFLOW` | `0` | `1` installs Airflow with a Git-Sync sidecar |
| `REPO_URL` / `REVISION` | git origin / current branch | What Argo CD and Git-Sync pull |
| `GITHUB_TOKEN` | – | Read-only token for a private repo |
| `BUILDER` | `auto` | `docker` or `buildah` |
| `IMPORT` | `auto` | `k3s`, `k3d` or `none` (how images reach the cluster) |
| `APP_DIR` | `./aks-microservices-app` | Path to the app repo if the repos are split |
| `EXTRA_BUILD_ARGS` | – | Extra build flags, e.g. a corporate proxy CA mount |
| `AIRFLOW_CHART` | Helm repo chart 1.22.0 | Local chart directory (offline or proxy setups) |
| `AIRFLOW_EXTRA_VALUES` | – | Extra Airflow values file (e.g. git-sync proxy env) |

URLs:

- Frontend: http://app.localtest.me. `*.localtest.me` resolves to 127.0.0.1.
- APIs: http://app.localtest.me/api/users (also `/api/products`, `/api/orders` and `/api/notifications`).
- Argo CD: http://argocd.localtest.me. User `admin`; `up.sh` prints the password.
- Airflow:
  ```bash
  kubectl -n airflow port-forward svc/airflow-api-server 8080:8080
  ```
  Then open http://localhost:8080 and log in as `admin`. `up.sh` prints the password.

---

## 4. Test the application and GitOps

```bash
aks-gitops-deployment/local/test.sh
```

| # | Section | What it proves |
|---|---|---|
| 1 | Platform | Nodes ready, all pods running, migration jobs complete |
| 2 | Ingress and routing | One host, five path routes, frontend served |
| 3 | Security behaviour | Security headers, internal API key enforced, non-root pods |
| 4 | PostgreSQL CRUD | user-service create, read, update and delete |
| 5 | Redis cache | product-service cache miss, then cache hit (`X-Cache`) |
| 6 | Order flow | order-service calls user-service and product-service; notification written to shared storage |
| 7 | Persistence | Data survives pod restarts |
| 8 | Database isolation | One service can't read another service's database |
| 9 | NetworkPolicy | Allowed paths work and denied paths are blocked (positive and negative controls) |
| 10 | GitOps (Argo CD) | Applications Synced and Healthy; self-heal reverts a manual change |
| 11 | Airflow | DAGs synced from Git and listed; `order_processing_pipeline` run succeeds |

### Manual GitOps exercises (Argo CD mode)

1. **Deploy by commit:** change `replicaCount` in `aks-gitops-deployment/local/values/frontend.yaml`, then commit and push. Argo CD scales the frontend within about 3 minutes (or click *Refresh*).
2. **Self-heal:**
   ```bash
   kubectl -n apps scale deploy/frontend --replicas=5
   ```
   Argo CD sets it back to the value in Git.
3. **Rollback:** `git revert` the commit and push. The previous state comes back.

---

## 5. Test DAG sync from Git (Git-Sync → Airflow)

How it works:

1. The Airflow DAG processor pod runs a **git-sync** sidecar.
2. Every 30 s, the sidecar pulls `aks-microservices-app/airflow/dags` from your GitHub branch into a shared volume.
3. Airflow parses that folder.

A merged pull request therefore reaches Airflow with **no image rebuild and no redeploy**. That is the same flow as on AKS (`values/airflow.yaml` → `dags.gitSync`).

### 5.1 Automated test

Basic check: the files were synced and the DAGs are registered with no import errors:

```bash
aks-gitops-deployment/local/test-dag-sync.sh
```

Full check: push a change, wait for Airflow to show it, then push the revert and wait again. This needs push rights on the branch:

```bash
BUMP=1 aks-gitops-deployment/local/test-dag-sync.sh
```

With `BUMP=1` the script:

1. Changes `DAG_VERSION` in `aks-microservices-app/airflow/dags/dag_sync_canary.py` (for example 1.0.0 → 1.0.1), then commits and pushes it.
2. Polls Airflow until the `dag_sync_canary` description shows `v1.0.1`, and prints how long that took.
3. Runs `git revert`, pushes, and waits for `v1.0.0` to come back (this tests rollback through Git).

Other options: `REVISION` (the branch Git-Sync follows), `TIMEOUT` (default 300 s), `TARGET=k8s|host`, and `AIRFLOW_NS`, `AIRFLOW_DEPLOY` and `AIRFLOW_CONTAINER`.

### 5.2 Manual test (Airflow UI)

1. Open the Airflow UI and find the DAG **dag_sync_canary**. Its description says `Git-Sync canary v1.0.0`.
2. Edit `DAG_VERSION` in `dag_sync_canary.py`, then commit and push (or merge a pull request) to the branch Git-Sync follows.
3. Within about 30–60 s the description changes to the new version. Watch the sync happen:
   ```bash
   kubectl -n airflow logs deploy/airflow-dag-processor -c git-sync -f
   ```
4. Add a new DAG file, push it, and it appears in the DAG list. Delete it, push, and it disappears.

### 5.3 Without k3s (quick host-only check)

You can test the Git-Sync → Airflow path with no cluster at all, using a git-sync v4 binary and Airflow from pip (Python 3.10–3.13).

1. Install Airflow with its constraints file:
   ```bash
   python3 -m venv .venv-af
   ```
   ```bash
   .venv-af/bin/pip install "apache-airflow==3.2.2" \
     --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.2.2/constraints-3.13.txt"
   ```
2. Set the Airflow environment:
   ```bash
   export AIRFLOW_HOME=$PWD/.af-home PATH=$PWD/.venv-af/bin:$PATH
   ```
   ```bash
   export AIRFLOW__CORE__DAGS_FOLDER=$PWD/.gitsync/repo/aks-microservices-app/airflow/dags
   ```
   ```bash
   export AIRFLOW__CORE__LOAD_EXAMPLES=False AIRFLOW__DAG_PROCESSOR__REFRESH_INTERVAL=10
   ```
3. Initialise the database:
   ```bash
   airflow db migrate
   ```
4. Start git-sync, pulling the branch every 10 s:
   ```bash
   git-sync --repo=https://github.com/<you>/GitOps-AKS --ref=<branch> \
     --root=$PWD/.gitsync --link=repo --period=10s --depth=1 &
   ```
5. Start the Airflow DAG processor:
   ```bash
   airflow dag-processor &
   ```
6. Run the test against the host:
   ```bash
   BUMP=1 TARGET=host aks-gitops-deployment/local/test-dag-sync.sh
   ```

---

## 6. Verified results

Run in the build environment (single-node k3s v1.34.1, images built with buildah):

| Test | Result |
|---|---|
| `MODE=helm up.sh` + `test.sh`, sections 1–9 | **30 passed, 0 failed** |
| Helm charts with AKS values | Render byte-identical to before the local changes, so local support doesn't change AKS |
| Git-Sync → Airflow 3.2.2: initial sync | All 3 DAGs registered, no import errors |
| Git-Sync → Airflow, run 1 (manual): push v1.0.1, then revert | Airflow showed v1.0.1 after **6 s** and back to v1.0.0 after **9 s** |
| Git-Sync → Airflow, run 2 (`BUMP=1 TARGET=host test-dag-sync.sh`) | **10 passed, 0 failed**. New version after **2 s**, rollback after **12 s** |

These timings used a 10 s sync period. The local and AKS values use 30 s, so expect up to about 30–60 s there.

**Not run in that environment:**

- Argo CD (section 10): its images are on quay.io.
- Airflow inside k3s with the chart's git-sync sidecar: the image is on registry.k8s.io, and Helm chart repositories were blocked by the build environment's network.

The Git-Sync → Airflow path was therefore tested with the same git-sync v4 and Airflow 3.2.2 running as host processes (section 5.3). On a normal laptop, `up.sh` pulls those images and both run inside k3s.

---

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| `ErrImageNeverPull` for `aks-poc/*` | Images not imported. Check `sudo k3s crictl images \| grep aks-poc`, then rerun `up.sh` or set `IMPORT` |
| App pods `Pending` with a `disk-pressure` taint | Free up disk. k3s evicts pods and deletes images when disk is low; rerun `up.sh` afterwards |
| Argo CD `ComparisonError` | Is the branch pushed? A private repo needs `GITHUB_TOKEN`. Check `kubectl -n argocd get applications` |
| `*-migrate` job failing | `kubectl -n data logs job/db-bootstrap`, then `kubectl -n apps logs job/<svc>-migrate` |
| DAGs not appearing | `kubectl -n airflow logs deploy/airflow-dag-processor -c git-sync`. Look for auth errors (private repo needs `GITHUB_TOKEN`), a wrong `REVISION`, or a proxy blocking github.com |
| DAG appears with an import error | `airflow dags list-import-errors` in the dag-processor pod |
| Git-Sync behind a corporate proxy | Pass `HTTPS_PROXY` and the CA bundle to the git-sync container with `AIRFLOW_EXTRA_VALUES` (`dags.gitSync.env`, `GIT_SSL_CAINFO`) |
| Airflow tasks stuck in queued | `kubectl -n airflow logs deploy/airflow-worker -c worker`; check the broker Secret `airflow-broker-url` |
| `app.localtest.me` not reachable | Is Traefik running (`kubectl -n kube-system get svc traefik`)? Is port 80 free? |

Clean up:

```bash
aks-gitops-deployment/local/down.sh
```

To also remove k3s:

```bash
/usr/local/bin/k3s-uninstall.sh
```
