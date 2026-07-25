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
├── day7-ingress-tls/      (namespace 'day7' — setup also installs ingress-nginx)
├── day8-pv-statefulset/   (namespace 'day8' — also creates 3 cluster-scoped PVs)
├── day9-daemonset-lifecycle/  (namespace 'day9')
├── day10-helm-webhooks/   (namespace 'day10' + 'day10-stuck' — setup also installs Helm)
│
│   Everything above runs on the shared LOCAL kind cluster. Everything
│   below runs on a REAL AKS cluster in Azure — separate infrastructure,
│   separate cost, separate kubectl context. See the "Day 11-15" section
│   below before running any of these.
│
├── day11-aks-acr-identity/         (namespace 'aks-day11')
├── day12-aks-storage-csi/          (namespace 'aks-day12')
├── day13-aks-networking-agic/      (namespace 'aks-day13')
├── day14-aks-rbac-aad/             (namespace 'aks-day14')
├── day15-aks-autoscaler-nodepools/ (namespace 'aks-day15')
├── day16-aks-egress-lockdown/      (namespace 'aks-day16')
├── day17-aks-snat-loadbalancer/    (namespace 'aks-day17')
└── day18-aks-keyvault-csi/         (namespace 'aks-day18' — also creates a real Key Vault)
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
| `00-reset-all-days.sh` (repo root) | Every namespace, cluster-wide scope | Wipes `dev`, `test` (Day-0), and `day1`..`day10` namespaces, plus the day4 ClusterRoleBinding, day8's 3 cluster-scoped PersistentVolumes, and day10's Helm releases/webhook/CRD/stuck namespace, in one shot — without touching the cluster itself. Delegates to day6's and day10's own cleanup scripts for the parts a plain namespace delete can't handle. Equivalent to running every day's own cleanup script back to back. |

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

**Day 8 creates 3 cluster-scoped PersistentVolumes** (`pv-1`, `pv-2`,
`pv-3`) alongside the `day8` namespace. PVs aren't namespaced, so a plain
`kubectl delete namespace day8` won't remove them — always use this
folder's own `02-cleanup-namespace.sh` (or the root
`00-reset-all-days.sh`), both of which delete the PVs explicitly.

**Day 10 requires `helm`**, which its `00-setup-cluster.sh` installs
automatically, and it's the most involved cleanup of any day: it tracks
Helm releases (which `kubectl delete namespace` doesn't know about), a
cluster-scoped `ValidatingWebhookConfiguration`, a cluster-scoped CRD, and
a **second namespace** (`day10-stuck`) that's deliberately left in
`Terminating` state as part of the exercise. Always use this folder's own
`02-cleanup-namespace.sh` — it handles all of that in the right order
(clearing finalizers before deleting the CRD, uninstalling Helm releases,
etc.) so nothing gets left behind or hangs.

## Day 11-15 — AKS (real Azure, not kind)

Everything from `Day-0` through `day10` runs on one local, free, kind
cluster. **`day11` through `day18` are fundamentally different**: they
require a real Azure subscription and create a real, billable AKS
cluster, because things like ACR authentication, Azure Disk/File CSI
zone behavior, Azure CNI IP exhaustion, AGIC, Azure AD RBAC integration,
and the cluster autoscaler's interaction with node pools cannot be
faithfully reproduced on kind at all — they depend on the real Azure
control plane.

**Before running any `day11`-`day18` folder:**
```bash
az login
az account set --subscription "<your-subscription-id-or-name>"
```
Each `dayN-aks-*/00-setup-cluster.sh` installs the Azure CLI if missing,
checks you're logged in (exits with instructions if not — it will never
run `az login` for you), and creates one shared AKS cluster
(`aks-practice` in resource group `aks-practice-rg`) that all 8 AKS
folders (`day11`-`day18`) use, mirroring how `day1`-`day10` share one
kind cluster.

**Cost and safety — read this before starting:**
- An AKS cluster is real, billable infrastructure (VMs, disks, and
  whatever else each day adds — an ACR in `day11`, extra node pools in
  `day15`, a Key Vault in `day18`, etc.). It is not free and not instant
  to provision (~5-15 minutes for cluster creation).
- **`00-reset-all-days.sh` at the repo root does NOT touch anything in
  day11-day18, on purpose.** Once you run `az aks get-credentials`, your
  `kubectl` context points at the real AKS cluster instead of kind — a
  script written assuming the local kind cluster could otherwise run
  destructive commands against real Azure resources if invoked while
  pointed at AKS. Clean up AKS-day resources only via each folder's own
  `02-cleanup-namespace.sh`, or fastest of all, delete the whole resource
  group when you're completely done:
  ```bash
  az group delete --name aks-practice-rg --yes --no-wait
  ```
- Check your current context before running ANY cleanup or reset script:
  `kubectl config current-context`. If it says something with `aks` in
  it, you're pointed at Azure, not kind.
- I have not been able to test any of the day11-18 scripts against a
  live Azure subscription (no Azure access in my environment). Syntax is
  checked and the concepts are accurate to how AKS actually behaves, but
  exact CLI flags/output text can drift across `az` CLI versions and
  Azure regions — treat these as a strong starting point to debug and
  adapt, not guaranteed-to-run-unmodified scripts. Some issues
  (`day13`'s AGIC scenario, `day14`'s Azure-RBAC-mode scenario, `day16`'s
  real-firewall scenario) are intentionally left as **guided manual
  exercises** rather than fully scripted, because fully automating them
  would require provisioning significant extra Azure infrastructure (an
  Application Gateway, a second cluster in Azure RBAC mode, an Azure
  Firewall + route table) that isn't practical to spin up
  unconditionally in a shared setup script. `day16` and `day17` also use
  Kubernetes NetworkPolicies to SIMULATE the symptom of egress
  lockdown/SNAT pressure rather than reproducing the real Azure-level
  mechanism exactly — the diagnostic instinct transfers, the underlying
  blocking mechanism doesn't. `day18` (Key Vault CSI) is fully scripted
  end-to-end, no manual steps required.

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

**Day 8 — PV/PVC & StatefulSet Lifecycle** (`day8`)
Deeper storage/StatefulSet scenarios than Day 2: a statically-provisioned
PV/PVC pair that never binds because of a label-selector mismatch, a PV
stuck in `Released` after its original PVC was deleted (with
`Retain` policy) blocking a brand-new PVC from reusing it, a PVC
requesting more capacity than the only matching PV offers, a StatefulSet
rolling update that appears "stuck" because a leftover
`updateStrategy.rollingUpdate.partition` value only updates the highest
ordinals, and a StatefulSet with default `OrderedReady` pod management
where pod-0 never becomes Ready — so pod-1 and pod-2 are never even
created.

**Day 9 — DaemonSets & Pod Lifecycle Timing** (`day9`)
A DaemonSet with a `nodeSelector` that quietly narrows it to fewer nodes
than expected ("DaemonSets run everywhere" isn't actually guaranteed), a
`hostPort` collision that blocks a DaemonSet pod on exactly one node, a
`PodDisruptionBudget` with `minAvailable` set so high it blocks node
drain entirely, a `preStop` hook that gets cut off by SIGKILL because
`terminationGracePeriodSeconds` is shorter than the hook itself takes,
and a `startupProbe` budget too small for the app's real startup time —
which looks identical to a crashing app but isn't one.

**Day 10 — Helm, Admission Webhooks & CRD/Namespace Lifecycle** (`day10`, requires `helm`)
A Helm chart's `required` guard catching a bad values override before
anything gets created, a `helm upgrade --atomic` that silently
auto-rolls-back after a bad image tag (nothing looks "currently broken",
which is the trap), a `ValidatingWebhookConfiguration` pointing at a
Service that doesn't exist — blocking all new pod creation in just this
namespace until fixed — a CRD installed with no controller behind it (a
custom resource that just sits there, reconciling nothing, with no
visible error), and a namespace deliberately stuck in `Terminating`
forever because a custom resource inside it carries a finalizer nothing
will ever remove — the last-resort manual-finalizer-removal fix, done
carefully.

**Day 11 — AKS: ACR & Workload Identity** (`aks-day11`, real Azure)
An ACR never attached to the cluster's managed identity (`ImagePullBackOff`
despite a correct image reference), a Workload Identity setup missing the
one pod-level label (`azure.workload.identity/use: "true"`) that actually
activates the token-injection webhook — everything else can look
perfectly configured and it still won't work — and an ACR pull secret
holding an expired/invalid credential despite being correctly wired up.

**Day 12 — AKS: Azure Disk/File CSI Storage** (`aks-day12`, real Azure)
A Premium disk StorageClass paired with a VM size that doesn't support
Premium attachment, an Azure Disk's zone-bound nature causing a "volume
node affinity conflict" when a rescheduled pod lands in a different
availability zone than its disk, and an Azure Files mount failing at the
data-plane level because the storage account's network rules block the
AKS subnet — while the PVC itself binds just fine.

**Day 13 — AKS: Azure CNI Networking & AGIC** (`aks-day13`, real Azure)
Azure CNI's per-node IP reservation (based on `--max-pods`, not actual
pod count) exhausting a small subnet's address space, an AGIC
Application Gateway backend reporting Unhealthy because its dedicated
subnet blocks AGIC's own required health-probe ports (guided manual
exercise — needs the AGIC add-on), and a NetworkPolicy that's silently
never enforced at all because the cluster has no network policy engine
enabled — the most dangerous kind of failure, since it looks like a
working control that simply never fires.

**Day 14 — AKS: Azure AD/Entra RBAC Integration** (`aks-day14`, real Azure)
A RoleBinding referencing a stale Azure AD group Object ID (group
recreated with the same name generates a brand-new ID), a cluster in
Azure RBAC mode where Kubernetes-native Role/RoleBinding objects are
silently ignored entirely in favor of Azure-side role assignments
(guided manual exercise), and a fully-reproducible local gotcha: using
`az aks get-credentials --admin` merges in a cert-based context that
bypasses Azure AD auth entirely, masking real RBAC problems behind
cluster-admin access without anyone noticing which context is active.

**Day 15 — AKS: Cluster Autoscaler & Node Pools** (`aks-day15`, real Azure)
Pods stuck Pending because the autoscaler is already at its configured
`max-count` ceiling (looks identical to autoscaler being disabled), a
tainted dedicated node pool that the autoscaler won't scale up because
the workload was never tolerating it in the first place, and a pod
annotated `cluster-autoscaler.kubernetes.io/safe-to-evict: "false"` that
permanently blocks scale-down consolidation on its node — invisible in
`kubectl get pods`, only visible via `describe` or `-o yaml`.

**Day 16 — AKS: Egress Lockdown / Outbound Restriction** (`aks-day16`, real Azure, partly simulated)
Image pulls and Azure AD token requests timing out because required
FQDNs (`mcr.microsoft.com`, `login.microsoftonline.com`, etc.) aren't
allow-listed on an outbound-restricted cluster — simulated here via
NetworkPolicy rather than a real Azure Firewall, since fully reproducing
`outboundType=userDefinedRouting` needs substantial extra infrastructure.
A guided walkthrough covers the real-world trap: firewall rules set up
once at cluster creation silently going stale as new AKS features get
enabled later, each needing their own FQDN allow-listed.

**Day 17 — AKS: SNAT & Load Balancer** (`aks-day17`, real Azure, partly illustrative)
A `LoadBalancer` Service referencing a static IP that was never actually
provisioned (stuck `EXTERNAL-IP <pending>` forever), a small-scale
illustration of the SNAT port exhaustion mechanism and which Azure Monitor
metric to check for it at real scale, and the classic
`azure-load-balancer-internal` annotation mix-up — a Service that looks
public because it says `type: LoadBalancer`, but got a private VNet IP
instead, with nothing anywhere flagged as an error.

**Day 18 — AKS: Key Vault Secrets Store CSI Driver** (`aks-day18`, real Azure, fully scripted)
Three increasingly specific failure points along the exact same request
path, deliberately structured to build a diagnostic ladder: a
`SecretProviderClass` pointing at a Key Vault that doesn't exist (clean
"vault not found"), the vault existing but the identity never granted
access (403 Forbidden — a completely different failure from the first,
despite both looking like "the pod won't start" from the outside), and
the vault + access both correct but the specific secret name was never
created in it ("secret not found," one level more specific still).

## Suggested pace

Work through `Day-0` first (both rounds) to build the core diagnostic
habits — `describe`/`logs`/`events` before anything else — then move
through `day1`..`day5` in order, one namespace at a time. `day8` pairs
well right after `day2` since both are storage-themed (`day8` is the
deeper, static-provisioning/StatefulSet-lifecycle follow-up to `day2`'s
dynamic-provisioning basics). `day9` fits naturally after `day8` since
both are workload-lifecycle-focused. Save `day6` and `day10` for last:
`day6` is the most advanced in terms of blast radius (node/control-plane/
etcd level, not just `kubectl`), and `day10` assumes comfort with
everything else since a broken webhook or stuck namespace is exactly the
kind of "everything else looks fine" incident that's hardest to diagnose
without the earlier days' habits. `day7` can slot in anywhere after
`day3` (networking fundamentals) since Ingress is really an extension of
Service routing. Each day/round is independent, so you can also jump
around or redo any of them from scratch using that folder's own cleanup
script plus its create-issues script, all without leaving that folder.
Use the repo-root `00-reset-all-days.sh` whenever you want a full clean
slate across `Day-0`..`day10` at once.

Treat `day11`..`day18` as a separate track entirely, done once you're
comfortable with the fundamentals above — they assume the same
diagnostic instincts, applied to Azure-specific failure surfaces. Since
they share one real AKS cluster and cost money while it exists, it's
worth working through all 8 in one focused session (or a couple of
sessions) rather than leaving the cluster running between visits, and
deleting the `aks-practice-rg` resource group the moment you're done.
Within that track, `day11`-`day15` are the more "core" AKS scenarios
(identity, storage, networking basics, RBAC, autoscaling); `day16`-`day18`
go a layer deeper into networking/secrets patterns most teams only
encounter once their cluster is handling real production traffic.
