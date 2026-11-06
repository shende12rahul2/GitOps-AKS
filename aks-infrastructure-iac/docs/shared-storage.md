# Azure Files shared storage

## Design

| Decision | Choice | Why |
|---|---|---|
| Protocol | **SMB 3.1.1** (Standard, transaction optimized) | Pay-as-you-go, no 100 GiB provisioned minimum, encryption in transit (AES-GCM) |
| Alternative | NFS 4.1 (Premium FileStorage) | POSIX ownership and better lock semantics, but provisioned capacity cost, no Kerberos identity, encryption in transit needs the EiT mount helper |
| Authentication | **Managed identity mount** (`mountWithManagedIdentity`, GA in the CSI driver >= 1.34): kubelet identity with *Storage File Data SMB MI Admin*, account has `smb_oauth_enabled`, **shared keys disabled** | No storage key anywhere (Git, Kubernetes Secrets, Terraform outputs) |
| Fallback auth | Account key retrieved by the driver through the kubelet identity | Only if MI mount is unavailable; requires `shared_access_key_enabled = true` |
| Provisioning | **Static**: Terraform creates `shared-files` and `airflow-logs`; Argo CD creates PV/PVC (`storageClassName: ""`, `claimRef`/`volumeName`) | One owner per share; no duplicate dynamic shares |
| Network | Private endpoint `privatelink.file.core.windows.net`, public access disabled | |
| Reclaim | `Retain`; PV/PVC never pruned | Data survives Argo CD deletes |

## Layout

```
/mnt/shared/
├── common/                 shared by all; unique file names or lock files
├── frontend/
├── user-service/
├── product-service/
├── order-service/
└── notification-service/   outbox/YYYY/MM/DD/<uuid>.json
```

Every service creates this layout idempotently at start-up (`mkdir -p`; safe
when pods start at the same time on different nodes). Each chart has
`sharedStorage.enabled`, `existingClaim`, `mountPath`, `readOnly`.

## Safe concurrent writes (implemented in `svc_common.shared_storage`)

1. **Atomic replace**: write `.<name>.<uuid>.tmp` in the target directory,
   `fsync`, then `os.replace()`. Readers on any node see the old or the new
   file, never a torn one (tested with 4 concurrent writers).
2. **Single writer per file**: services write only under their own directory or
   use UUID file names in `common/`; enforced by the helper (403 otherwise).
3. **Cross-node mutual exclusion**: lock files created with
   `O_CREAT | O_EXCL` (atomic on the SMB server), with stale-lock expiry. Used for
   the daily notification summary (read-modify-write).
4. Byte-range locks: the PV omits `nobrl`, so fcntl locks are sent to the server;
   still prefer the patterns above (SMB oplocks + `cache=strict` cache coherently,
   but advisory locking across clients is easy to misuse).
5. Path traversal protection: every path must resolve under the mount.

## Permissions and isolation limits

- SMB has no per-file POSIX ownership: the mount presents every file as
  `uid=10001,gid=10001` with `dir_mode=0770,file_mode=0660`. All app containers
  run as 10001, so **any service can technically write any directory**; the
  per-service directory rule is enforced by application code, not by the OS.
- The kubelet identity (one per node pool) performs the mount, so Azure cannot
  distinguish which service wrote a file.
- For hard isolation use one share (and PV) per service, or NFS with distinct
  UIDs, or separate storage accounts per data classification.
- Airflow logs use a separate share mounted as `uid=50000,gid=0`.

## Quotas and monitoring

- Share quotas: `shared-files` 10 GiB, `airflow-logs` 10 GiB (dev); alert at 80 %
  (`FileCapacity` per share), PVC usage alert (managed Prometheus).
- Transactions are billed on Standard shares; logs/notifications are small files,
  keep log retention short (Airflow logs cleanup is a production follow-up).

## Recovery

- Share soft delete (7 days): `az storage share-rm restore`.
- Azure Backup for file shares (snapshots) recommended for production.
- `Retain` reclaim policy keeps data if PV/PVC are deleted; re-create the PV with
  the same `volumeHandle` to re-attach.

## Cross-node validation

`aks-gitops-deployment/scripts/validate-shared-storage.sh <env>` runs the full
scenario with two pods pinned to two different nodes (`nodeName`):

| Step | Action | Expected |
|---|---|---|
| 1-2 | pod A on node 1, pod B on node 2 | both Ready, same PVC |
| 3 | A writes `common/cross-node-test-*.txt` | ok |
| 4 | B reads it | content from A |
| 5 | B appends | ok |
| 6 | A reads | both lines |
| 7 | delete + recreate both pods | file intact |
| 8 | swap nodes | file intact |
| 9 | verify, clean up | PASS |

Application-level check: Airflow DAG `shared_storage_check` and
`GET /api/<svc>/shared/selftest` on every service. The frontend dashboard shows
notification files written by `notification-service` together with the pod and
node that wrote them.
