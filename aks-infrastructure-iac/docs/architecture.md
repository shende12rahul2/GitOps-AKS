# Architecture

Azure AKS enterprise POC: private AKS, managed data services, GitOps delivery.
All diagrams are Mermaid (rendered by GitHub).

## 1. Ownership boundaries

| Layer | Owner | Tool | Repository | Examples |
|---|---|---|---|---|
| Azure resources | Platform team | Terraform (GitHub Actions + OIDC) | `aks-infrastructure-iac` | VNet, AKS, App Gateway, ACR, Key Vault, PostgreSQL, Managed Redis, Storage, identities, RBAC, monitoring |
| Secret values | Terraform (generated) / operators (external) | ARM control plane, `set-operator-secret.sh` | none (Key Vault only) | DB password, broker URL, Fernet key, deploy keys, OAuth secret |
| Kubernetes resources | Argo CD | Helm charts + values | `aks-gitops-deployment` | namespaces, policies, PV/PVC, Airflow, the five services, Ingress, certificates |
| Images and DAGs | Application teams | GitHub Actions (CI only, no AKS access) | `aks-microservices-app` | service images, Airflow image, db-bootstrap image, DAG files |
| DAG delivery | Airflow Git-Sync | git (SSH deploy key, read-only) | `aks-microservices-app/airflow/dags` | DAG files only |

Rules that keep the boundaries clean:

- Terraform never talks to the Kubernetes API (the API server is private; no Helm/Kubernetes providers). Argo CD is bootstrapped once by `argocd/bootstrap/install.sh`.
- Argo CD never creates Azure resources. Azure facts reach Git through a generated, non-secret contract file (`environments/<env>/infrastructure.yaml`, produced by `scripts/export-gitops-values.sh`).
- CI never deploys. It pushes immutable images and opens a pull request in the GitOps repo; merging that PR is the deployment approval.
- Terraform owns the Azure Files shares; Kubernetes binds to them with static PersistentVolumes (no dynamic provisioning of the same share).
- Terraform creates the PostgreSQL server; databases, roles and grants are SQL in a versioned Job (`db-bootstrap`), because ARM-created databases are owned by an internal role.

## 2. High-level design

```mermaid
flowchart LR
  subgraph GH[GitHub]
    IAC[aks-infrastructure-iac]
    APP[aks-microservices-app]
    OPS[aks-gitops-deployment]
  end
  subgraph AZ[Azure subscription - one VNet per environment]
    subgraph NET[Foundation]
      VNET[(VNet 10.x.0.0/16)]
      DNS[(Private DNS zones)]
    end
    subgraph PLT[Platform]
      AGW[App Gateway WAF_v2<br/>private frontend]
      AKS[AKS private cluster<br/>CNI Overlay + Cilium]
      ACR[(ACR)]
      KV[(Key Vault)]
      MON[(Log Analytics +<br/>Managed Prometheus)]
    end
    subgraph DATA[Data]
      PG[(PostgreSQL Flexible<br/>VNet-integrated)]
      RDS[(Azure Managed Redis<br/>private endpoint)]
      FILES[(Azure Files SMB<br/>private endpoint)]
    end
  end
  IAC -- terraform plan/apply<br/>OIDC --> AZ
  APP -- build + push<br/>OIDC --> ACR
  APP -- PR with digests --> OPS
  OPS -- pull (Argo CD) --> AKS
  APP -- Git-Sync (DAGs) --> AKS
  AGW --> AKS
  AKS --> PG & RDS & FILES & KV
  AKS -. pull .-> ACR
  AKS -. logs/metrics .-> MON
```

## 3. Low-level design (in-cluster)

```mermaid
flowchart TB
  subgraph AKS[AKS cluster]
    subgraph SYS[system pool - CriticalAddonsOnly]
      CDNS[CoreDNS] & AGIC[AGIC add-on] & CSI[CSI drivers<br/>Azure Files, Key Vault] & AMA[ama-logs / ama-metrics]
    end
    subgraph USR[user pool 'apps' - 2 x D4ads_v5]
      subgraph NSA[ns: apps - PSS restricted, default-deny]
        FE[frontend] --> US[user-service] & PS[product-service] & OS[order-service]
        OS --> US & PS & NS[notification-service]
      end
      subgraph NSF[ns: airflow - PSS baseline]
        API[api-server] --- SCH[scheduler] --- DP[dag-processor + git-sync]
        W[celery worker + git-sync] --- TR[triggerer] --- KVS[kv-sync]
      end
      subgraph NSJ[ns: platform-jobs]
        DBB[db-bootstrap Job]
      end
      subgraph NSC[ns: argocd / cert-manager]
        ARGO[Argo CD] & CM[cert-manager]
      end
    end
  end
  W -->|HTTP + X-API-Key| US & PS & OS & NS
  FE & US & PS & OS & NS ---|RWX PVC /mnt/shared| FILES[(Azure Files)]
  US & PS & OS -->|Entra token| PG[(PostgreSQL)]
  PS & OS -->|Entra token, TLS 10000| R[(Managed Redis)]
  SCH & W & API -->|password from KV| PG
  SCH & W -->|access key from KV, TLS| R
  W & API ---|RWX PVC airflow-logs| FILES
  DBB -->|Entra admin| PG
```

## 4. Azure network topology

```mermaid
flowchart TB
  subgraph VNET["vnet-akspoc-dev-eus2 10.10.0.0/16"]
    N["snet-aks-nodes 10.10.0.0/22<br/>nodes only - pods use overlay 192.168.0.0/16<br/>internal LB IP 10.10.3.232 (internal mode)"]
    G["snet-appgw 10.10.4.0/24<br/>App Gateway private IP 10.10.4.10<br/>(delegated when private-only)"]
    P["snet-private-endpoints 10.10.5.0/24<br/>pe-kv (443), pe-file (445), pe-redis (10000), pe-acr (prod)"]
    D["snet-postgresql 10.10.6.0/27<br/>delegated Microsoft.DBforPostgreSQL"]
    M["snet-mgmt 10.10.7.0/27<br/>jumpbox (optional)"]
    B["AzureBastionSubnet 10.10.7.64/26<br/>(Bastion Standard only)"]
  end
  Z1["privatelink.vaultcore.azure.net"] -.-> P
  Z2["privatelink.file.core.windows.net"] -.-> P
  Z3["privatelink.redis.azure.net"] -.-> P
  Z4["akspoc-dev-eus2.private.postgres.database.azure.com"] -.-> D
  Z5["poc.example.com (app/argocd/airflow A records)"] -.-> G
  Z6["privatelink.eastus2.azmk8s.io (AKS-managed)"] -.-> N
  N -- "egress: Standard LB outbound (POC)<br/>NAT Gateway / Azure Firewall (prod)" --> INET((Internet:<br/>Entra ID, GitHub, MCR))
```

Every subnet has `default_outbound_access_enabled = false`; NSGs deny VNet-wide
traffic except the explicitly allowed paths (see [network-design.md](network-design.md)).

## 5. Traffic flows

### 5.1 User to application (HTTPS)

```mermaid
sequenceDiagram
  autonumber
  participant B as Browser (VNet / VPN / jumpbox)
  participant D as Private DNS poc.example.com
  participant G as App Gateway WAF_v2 (10.10.4.10)
  participant F as frontend pod
  participant S as backend pod
  B->>D: app.poc.example.com?
  D-->>B: 10.10.4.10
  B->>G: HTTP :80
  G-->>B: 301 -> https (AGIC ssl-redirect)
  B->>G: HTTPS :443 (TLS 1.2+, cert from cert-manager via AGIC)
  G->>G: WAF DRS 2.1 + bot rules + rate limit
  alt path = /
    G->>F: HTTP to pod IP :8000 (overlay route)
  else path = /api/users|products|orders|notifications
    G->>S: HTTP to pod IP :8000
  end
  S-->>G: response + HSTS/security headers
  G-->>B: response
```

AGIC programs listeners, path maps and health probes (from each pod's readiness
probe) from the Kubernetes `Ingress`. Individual services are `ClusterIP` only.
The optional public WAF frontend (`appgw_public_frontend_enabled`, prod) binds
only the application hostname; admin hostnames always use the private IP.

### 5.2 Application to application

```mermaid
sequenceDiagram
  participant FE as frontend
  participant OS as order-service
  participant US as user-service
  participant PS as product-service
  participant NS as notification-service
  FE->>OS: POST /api/orders (X-API-Key)
  OS->>US: GET /api/users/{id} (cached in Redis 300 s)
  OS->>PS: POST /api/products/{id}/reserve (atomic conditional UPDATE)
  Note over OS,PS: on failure: release reserved stock (compensation)
  OS-->>FE: 201 PENDING
  FE->>OS: POST /api/orders/{id}/process
  OS->>NS: POST /api/notifications
  NS->>NS: atomic write /mnt/shared/notification-service/outbox/...json
```

Kubernetes DNS (`<svc>.apps.svc.cluster.local`), plain HTTP inside the cluster,
NetworkPolicy allow-lists per callee, API key for writes. Production upgrade:
mTLS (Istio add-on) and Entra-issued tokens instead of a shared key.

### 5.3 Application to PostgreSQL

```mermaid
sequenceDiagram
  participant P as user-service pod (SA user-service)
  participant WI as Workload identity webhook / Entra ID
  participant DNS as Private DNS
  participant PG as PostgreSQL (10.10.6.x:5432)
  P->>WI: projected SA token -> Entra token (scope ossrdbms-aad)
  P->>DNS: psql-...postgres.database.azure.com
  DNS-->>P: 10.10.6.x
  P->>PG: TLS, user = id-akspoc-dev-eus2-user-service, password = Entra token
  PG-->>P: session as role mapped to the identity's object ID (owner of users_db objects)
```

### 5.4 Application to Redis

`product-service` and `order-service` authenticate with Entra ID (redis-entraid
credential provider, background token refresh) over TLS to
`<name>.eastus2.redis.azure.net:10000`, which resolves to the private endpoint.
Keys are namespaced `app:<service>:...` and always set with a TTL. Airflow uses
the same instance with the access key (`airflow:` prefix).

### 5.5 Application to Azure Files

The kubelet identity mounts `//<account>.file.core.windows.net/shared-files`
(private endpoint, SMB 3.1.1, AES-GCM, Kerberos/SMB OAuth) once per node; pods on
any node see the same files at `/mnt/shared`. See [shared-storage.md](shared-storage.md).

### 5.6 Airflow to application

Celery workers (namespace `airflow`) call `http://<svc>.apps.svc.cluster.local:8000`
through Airflow HTTP connections; the `X-API-Key` header comes from the Key Vault
secret `internal-api-key`. Allowed by the `airflow` egress policy and each
service's `allowFromAirflow` ingress rule.

### 5.7 Administrator to AKS API

```mermaid
flowchart LR
  A[Administrator] -->|1. az aks command invoke<br/>ARM, no network path| ARM[(Azure Resource Manager)] --> API[Private API server]
  A -->|2. Bastion -> jumpbox in snet-mgmt| J[jumpbox] -->|kubectl + kubelogin, Entra| API
  A -->|3. VPN / ExpressRoute / peered hub (production)| API
```

Authentication is Entra ID (kubelogin); local accounts are disabled.
Authorization is Azure RBAC for Kubernetes plus Kubernetes RBAC RoleBindings.

### 5.8 CI/CD to Azure

GitHub Actions authenticate to Entra ID with OIDC federated credentials:

| Workflow | Identity | Federated subject | Permissions |
|---|---|---|---|
| terraform-plan | `id-akspoc-github-tf-<env>-plan` | `repo:<org>/aks-infrastructure-iac:pull_request` | Reader + state blob lock |
| terraform-apply | `id-akspoc-github-tf-<env>-apply` | `...:environment:<env>` | Contributor + constrained RBAC admin + state |
| build (app) | `id-akspoc-dev-eus2-github-acr` | `repo:<org>/aks-microservices-app:ref:refs/heads/main` | AcrPush (dev ACR) |
| promote (app) | `id-akspoc-<env>-eus2-github-acr` | `...:environment:<env>` | AcrPush target + AcrPull source |
| GitOps PR | GitHub App (no Azure) | — | contents/pull-requests on the GitOps repo |

No Azure identity can reach the Kubernetes API from CI.

## 6. Ingress and routing

| Host | Path | Backend | Frontend IP | Auth |
|---|---|---|---|---|
| `app.poc.example.com` | `/` | `frontend:8000` | private (public optional) | none (demo) / CSRF on forms |
| `app.poc.example.com` | `/api/users` | `user-service:8000` | same | API key for writes |
| `app.poc.example.com` | `/api/products` | `product-service:8000` | same | API key for writes |
| `app.poc.example.com` | `/api/orders` | `order-service:8000` | same | API key for writes |
| `app.poc.example.com` | `/api/notifications` | `notification-service:8000` | same | API key for writes |
| `argocd.poc.example.com` | `/` | `argocd-server:80` | private only | Entra SSO (workload identity) |
| `airflow.poc.example.com` | `/` | `airflow-api-server:8080` | private only | Entra SSO (FAB OAuth, app roles) |

Services serve their full prefix, so no path rewrite is needed. Both ingress
modes are selected by one setting each in Terraform (`ingress_mode`) and GitOps
(`ingressMode`, `global.ingress.mode`); never both:

| | `agic` (default) | `internal` (low cost) |
|---|---|---|
| Edge | Application Gateway WAF_v2 (or Standard_v2) | Traefik v3 behind internal Standard LB |
| WAF | DRS 2.1, bot manager, rate limit | none (add WAF upstream if needed) |
| TLS | cert-manager secret uploaded by AGIC; TLS policy 2022 | cert-manager secret at Traefik |
| Redirect / HSTS | AGIC annotation / app headers | entrypoint redirect / Middleware |
| Fixed cost | App Gateway hourly fee | 2 small pods + LB rule |
