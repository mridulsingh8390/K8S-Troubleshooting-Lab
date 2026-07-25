# Kubernetes Troubleshooting Practice — 5-Day Curriculum

Builds on the dev/test round1+round2 exercises with new failure classes,
one theme per day. Each day folder is **fully self-contained** — cluster
setup, issue seeding, namespace cleanup, and full cluster teardown all
live inside it. You never need to open another folder.

## Structure

```
k8s-practice/
├── 00-reset-all-days.sh          # optional: wipe day1..day5 namespaces in one shot
├── day1-workloads/
│   ├── 00-setup-cluster.sh       # installs docker/kubectl/kind, creates the cluster (k8s v1.34)
│   ├── 01-create-issues.sh       # seeds namespace 'day1' with 5 broken workloads
│   ├── 02-cleanup-namespace.sh   # deletes namespace 'day1' only
│   └── 03-delete-cluster.sh      # deletes the ENTIRE kind cluster
├── day2-storage/          (same 4 scripts, namespace 'day2')
├── day3-networking/       (same 4 scripts, namespace 'day3')
├── day4-security-rbac/    (same 4 scripts, namespace 'day4')
└── day5-jobs-quotas/      (same 4 scripts, namespace 'day5')
```

## How to use any single day folder

```bash
cd day1-workloads
chmod +x *.sh

./00-setup-cluster.sh          # only needed once — skips reinstall/recreate if already done
./01-create-issues.sh          # seeds the day's 5 issues
# ... troubleshoot on your own, using kubectl describe/logs/get events ...
./02-cleanup-namespace.sh      # clears just this day's namespace, try again with 01
```

**Important:** `00-setup-cluster.sh` is safe to run from *any* day folder —
it checks whether Docker/kubectl/kind/the cluster already exist and skips
anything already in place. So even though the script is duplicated across
all 5 folders, running it multiple times (once per day, or just once ever)
has the same end result: one shared `kind-practice` cluster that every
day's namespace lives in side by side.

## Script reference

| Script | Scope | What it does |
|---|---|---|
| `00-setup-cluster.sh` | Cluster-wide | Installs Docker/kubectl/kind if missing, creates a 3-node kind cluster pinned to Kubernetes v1.34. Idempotent — safe to re-run. |
| `01-create-issues.sh` | This day's namespace | Seeds 5 broken resources named `app-1`..`app-5`. Answer key is in the script's comments only. |
| `02-cleanup-namespace.sh` | This day's namespace | Deletes only this day's namespace, leaving the cluster and other days' namespaces intact. Use this to retry a day from scratch. |
| `03-delete-cluster.sh` | Cluster-wide | Deletes the entire kind cluster (every day, every namespace). Use only when fully done, or to force a clean rebuild. |

`00-reset-all-days.sh` at the repo root is a convenience script that wipes
all 5 namespaces (day1..day5) plus the day4 ClusterRoleBinding in one
shot, without touching the cluster itself — equivalent to running each
day's `02-cleanup-namespace.sh` back to back.

## Day-by-day themes

**Day 1 — Core Workloads** (`day1`)
Deployment/ReplicaSet failures beyond the basics: a Deployment referencing
a nonexistent ServiceAccount (no pod ever gets created — check the
ReplicaSet, not the pod), a missing command binary, a bad image digest,
an impossible pod anti-affinity requirement, and a liveness probe on the
wrong port causing endless restarts of an otherwise-healthy container.

**Day 2 — Storage & Persistence** (`day2`)
PVC binding failures (`storageClassName: ""` with no static PV,
ReadWriteMany requested against a StorageClass that doesn't support it),
a "volume node affinity conflict" from scaling a local-path-backed PVC to
2 replicas, an `emptyDir` size limit causing an eviction, and a container
trying to write into a read-only ConfigMap volume.

**Day 3 — Networking & Service Discovery** (`day3`)
A NetworkPolicy that allows the wrong port, a Service `targetPort`
mismatch, a pod with `dnsPolicy: None` and no DNS config at all, a Service
selector requiring two labels where the pod only has one, and an
egress NetworkPolicy that accidentally blocks DNS itself (port 53).

**Day 4 — RBAC & Pod Security** (`day4`, CKS-flavored)
An RBAC Role missing the `list` verb, a RoleBinding with a typo'd
ServiceAccount subject name, `runAsNonRoot: true` against an image that
only runs as root, a `restricted` Pod Security Admission namespace
rejecting a `hostNetwork` pod (Deployment applies fine, but its pods never
get created — check the ReplicaSet events), and an audit-style challenge:
find and remove an over-broad `cluster-admin` ClusterRoleBinding.

**Day 5 — Jobs, Quotas & Autoscaling** (`day5`)
A Job that exhausts its `backoffLimit` and fails, an invalid CronJob
schedule string, a `ResourceQuota` blocking new pod creation, a
`LimitRange` default memory limit causing an unexpected OOMKilled, and an
HPA pointing at a Deployment name that doesn't exist.

## Suggested pace

One day's namespace at a time — resolve everything in `day1` before
moving to `day2`, etc. Each day is independent, so you can also jump
around or revisit a day with `02-cleanup-namespace.sh` +
`01-create-issues.sh` to redo it from scratch, all without leaving that
day's folder.
