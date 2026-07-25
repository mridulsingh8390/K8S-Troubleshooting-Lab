# Kubernetes Troubleshooting Lab

A self-paced troubleshooting curriculum: `Day-0` covers the fundamentals
(pod-level failures across two rounds), then `day1`..`day5` each cover a
distinct theme. Every folder is **fully self-contained** for its own
cluster setup and cleanup — you never need to open another folder to run
a given day, and `00-reset-all-days.sh` at the repo root can wipe
everything across every day in one shot.

## Structure

```
K8S-Troubleshooting-Lab/
├── 00-reset-all-days.sh          # wipes every namespace across Day-0..day5 in one shot
├── Day-0/
│   ├── 00-reset-namespaces.sh    # wipes & recreates 'dev' and 'test'
│   ├── 01-setup-kind-cluster.sh  # installs docker/kubectl/kind, creates the cluster (k8s v1.34)
│   ├── 02-create-issues-round1.sh # seeds 'dev' + 'test' with 10 issues (app-1..app-5 each)
│   ├── 03-create-issues-round2.sh # seeds 'dev' + 'test' with 10 more issues (app-6..app-10 each)
│   ├── 04-cleanup-round1.sh      # removes only the round 1 resources
│   └── 05-cleanup-round2.sh      # removes only the round 2 resources
├── day1-workloads/
│   ├── 00-setup-cluster.sh       # installs docker/kubectl/kind, creates the cluster (k8s v1.34)
│   ├── 01-create-issues.sh       # seeds namespace 'day1' with 5 broken workloads
│   ├── 02-cleanup-namespace.sh   # deletes namespace 'day1' only
│   └── 03-delete-cluster.sh      # deletes the ENTIRE kind cluster
├── day2-storage/          (same 4 scripts, namespace 'day2')
├── day3-networking/       (same 4 scripts, namespace 'day3')
├── day4-security-rbac/    (same 4 scripts, namespace 'day4')
├── day5-jobs-quotas/      (same 4 scripts, namespace 'day5')
├── day6-control-plane/    (namespace 'day6' — ADVANCED, see warning below)
└── day7-ingress-tls/      (namespace 'day7' — setup also installs ingress-nginx)
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

`Day-0` follows the same pattern but with its own script names
(`01-setup-kind-cluster.sh`, `02-create-issues-round1.sh` /
`03-create-issues-round2.sh`, `04-cleanup-round1.sh` /
`05-cleanup-round2.sh`) since it predates the `day1`..`day5` numbering
convention and splits its 20 issues into two rounds instead of one batch
of 5.

**Important:** every `*-setup-*cluster.sh` script (in `Day-0` and in each
`dayN` folder) is safe to run from *any* folder — each checks whether
Docker/kubectl/kind/the cluster already exist and skips anything already
in place. So no matter which folder you start from, running its setup
script once is enough; you end up with one shared `kind-practice` cluster
that every day's namespaces live in side by side.

## Script reference

| Script | Scope | What it does |
|---|---|---|
| `*-setup-*cluster.sh` | Cluster-wide | Installs Docker/kubectl/kind if missing, creates a 3-node kind cluster pinned to Kubernetes v1.34. Idempotent — safe to re-run from any folder. |
| `*-create-issues*.sh` | That day's namespace(s) | Seeds broken resources named `app-N`. Answer key is in each script's comments only. |
| `*-cleanup*.sh` | That day's namespace(s) | Deletes only that day's (or that round's) resources, leaving the cluster and other days intact. Use to retry from scratch. |
| `03-delete-cluster.sh` (day1..day5 only) | Cluster-wide | Deletes the entire kind cluster (every day, every namespace). Use only when fully done, or to force a clean rebuild. |
| `00-reset-all-days.sh` (repo root) | Every namespace, cluster-wide scope | Wipes `dev`, `test` (Day-0), and `day1`..`day7` namespaces, plus the day4 ClusterRoleBinding, in one shot — without touching the cluster itself. Delegates to day6's own cleanup script to also revert its node/static-pod changes. Equivalent to running every day's own cleanup script back to back. |

**Day 6 is different from the others**: its `01-create-issues.sh` reaches
into the kind node containers directly via `docker exec` (editing static
pod manifests, stopping kubelet, filling disk) rather than only using
`kubectl`. Two of its five issues (`app-1`, `app-2`) temporarily affect
**the whole cluster's** scheduling/reconciliation, not just namespace
`day6`, until fixed. Its own `02-cleanup-namespace.sh` reverts node-level
state as well as deleting the namespace — always use that script (or the
root `00-reset-all-days.sh`) rather than a plain `kubectl delete namespace
day6` when you're done. If you ever get it into a confusing state,
`03-delete-cluster.sh` + a fresh `00-setup-cluster.sh` is a safe full
rebuild.

**Day 7 requires `ingress-nginx`**, which its `00-setup-cluster.sh`
installs automatically (the other days' setup scripts don't). This kind
cluster has no host port-mapping for 80/443, so Ingress testing happens
from inside the cluster via the `curl-debug` pod and a `Host` header —
see the comments at the top of `day7-ingress-tls/01-create-issues.sh` for
the exact command.

## Day-by-day themes

**Day 0 — Fundamentals** (`dev` + `test`, 20 issues across 2 rounds)
Round 1: the core five failure states (`CreateContainerConfigError`,
`ImagePullBackOff`, `CrashLoopBackOff`, `Pending`, Running-but-not-Ready)
in both namespaces with different root causes each. Round 2: StatefulSet
storage issues, an init-container that never completes, a broken TLS
Secret, a ConfigMap `subPath` mismatch, a default-deny NetworkPolicy, a
StatefulSet missing its headless Service, a crashing sidecar, a Secret
volume key mismatch, an RWX PVC on incompatible storage, and a malformed
ConfigMap env key.

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

**Day 6 — Node & Control Plane** (`day6`, CKA disaster-recovery flavored — ADVANCED)
A broken kube-scheduler static pod manifest (cluster-wide: new pods stop
getting scheduled anywhere), a broken kube-controller-manager static pod
manifest (cluster-wide: Deployments stop reconciling into pods), a
stopped kubelet on a worker node (NotReady), a "noisy neighbor" pod
without resource/volume limits filling real node disk and risking
DiskPressure for its neighbors, and a full etcd backup/restore exercise —
a critical ConfigMap is snapshotted then "accidentally" deleted, and your
job is to restore it from the etcd snapshot using the standard CKA
procedure.

**Day 7 — Ingress & TLS** (`day7`, requires `ingress-nginx`)
An Ingress backend pointing at a Service port that doesn't exist (503), a
missing `ingressClassName` so the Ingress is silently never adopted by
the controller, `pathType: Exact` where `Prefix` was needed (404 on
sub-paths), a TLS `secretName` that references a Secret which was never
created, and two Ingress objects claiming the identical host+path with
different backends — an unpredictable-routing conflict you have to spot
and resolve.

## Suggested pace

Work through `Day-0` first (both rounds) to build the core diagnostic
habits — `describe`/`logs`/`events` before anything else — then move
through `day1`..`day5` in order, one namespace at a time. Save `day6`
for last: it's the most advanced (node/control-plane/etcd level, not just
`kubectl`) and builds directly on everything practiced in the earlier
days. `day7` can slot in anywhere after `day3` (networking fundamentals)
since Ingress is really an extension of Service routing. Each day/round
is independent, so you can also jump around or redo any of them from
scratch using that folder's own cleanup script plus its create-issues
script, all without leaving that folder. Use the repo-root
`00-reset-all-days.sh` whenever you want a full clean slate across
everything at once.
