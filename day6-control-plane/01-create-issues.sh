#!/usr/bin/env bash
# day6-control-plane/01-create-issues.sh
# Namespace: day6 (plus node-level and control-plane-level changes)
#
# THIS DAY IS DIFFERENT from day1-day5: those only ever touched
# Kubernetes objects via kubectl. This one reaches into the kind node
# containers themselves via `docker exec` to break kubelet and static
# control-plane pods — the same class of failure you'd hit doing real
# cluster administration (and the same class you hit in your original
# interview exercise).
#
# Because of that, this is HIGHER RISK than other days:
#   - app-1/app-2 temporarily break scheduling/reconciliation cluster-wide
#     (not just in namespace day6) until fixed.
#   - app-3 takes a whole worker node NotReady until fixed.
#   - If you get stuck beyond recovery, 03-delete-cluster.sh + a fresh
#     00-setup-cluster.sh is always a safe fallback — that's what it's
#     there for.
#
# Comments are the answer key — avoid reading them until you're stuck.
#
# Usage: chmod +x 01-create-issues.sh && ./01-create-issues.sh

set -euo pipefail
NS="day6"
CP_NODE="practice-control-plane"
WORKER_NODE="practice-worker"
WORKER2_NODE="practice-worker2"

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

# [ANSWER KEY - app-1]: kube-scheduler's static pod manifest gets a bogus
# flag appended, so the kubelet can never start it successfully. The API
# server stays up (kubectl still works), but NEW pods anywhere in the
# cluster get stuck Pending forever — nothing is assigning them to nodes.
# Fix: docker exec onto ${CP_NODE}, inspect/edit
# /etc/kubernetes/manifests/kube-scheduler.yaml, remove the bad flag, save
# — the kubelet will pick up the change automatically.
echo "==> [app-1] Breaking kube-scheduler's static pod manifest on ${CP_NODE}..."
docker exec "${CP_NODE}" sed -i \
  '/- kube-scheduler/a\    - --this-flag-does-not-exist=true' \
  /etc/kubernetes/manifests/kube-scheduler.yaml

# [ANSWER KEY - app-2]: kube-controller-manager's static pod manifest gets
# a similar bogus flag. The API server and scheduler stay up, but
# Deployments/ReplicaSets stop reconciling — creating a Deployment
# succeeds as an object, but no ReplicaSet/pods ever get created for it.
# Fix: same pattern as app-1, but on
# /etc/kubernetes/manifests/kube-controller-manager.yaml.
echo "==> [app-2] Breaking kube-controller-manager's static pod manifest on ${CP_NODE}..."
docker exec "${CP_NODE}" sed -i \
  '/- kube-controller-manager/a\    - --this-flag-does-not-exist=true' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml

# [ANSWER KEY - app-3]: kubelet is stopped on ${WORKER2_NODE}. That node
# will flip to NotReady within ~40s, and pods already on it will
# eventually be evicted/rescheduled elsewhere. Fix: docker exec onto
# ${WORKER2_NODE} and `systemctl start kubelet` (check `systemctl status
# kubelet` / `journalctl -u kubelet` first, the way you would on a real
# NotReady node).
echo "==> [app-3] Stopping kubelet on ${WORKER2_NODE}..."
docker exec "${WORKER2_NODE}" systemctl stop kubelet

# [ANSWER KEY - app-4]: A "noisy neighbor" pod with an unbounded emptyDir
# writes ~3GiB to disk on ${WORKER_NODE}, pinned there via nodeSelector.
# On a small kind node this can be enough to trip the kubelet's
# DiskPressure threshold (default: less than 10% of the filesystem free),
# which taints the node and can trigger eviction of OTHER pods sharing it
# — a real "one bad pod without limits affects everyone else on the node"
# scenario. Fix: delete this pod (frees the disk immediately), and in a
# real cluster you'd also add an emptyDir sizeLimit or a ResourceQuota to
# prevent recurrence. NOTE: this writes real disk to your Ubuntu host —
# ~3GiB, not unbounded — clean up promptly with 02-cleanup-namespace.sh
# if you're tight on disk space.
echo "==> [app-4] Deploying a noisy-neighbor pod that fills disk on ${WORKER_NODE}..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-4
  namespace: ${NS}
spec:
  nodeSelector:
    kubernetes.io/hostname: ${WORKER_NODE}
  containers:
    - name: app
      image: busybox:1.36
      command:
        - sh
        - -c
        - |
          i=0
          while [ \$i -lt 3 ]; do
            dd if=/dev/zero of=/data/fill-\$i bs=1M count=1024 2>/dev/null
            i=\$((i+1))
          done
          sleep infinity
      volumeMounts:
        - {name: scratch, mountPath: /data}
  volumes:
    - name: scratch
      emptyDir: {}
EOF

# [ANSWER KEY - app-5]: etcd backup/restore exercise. A ConfigMap holding
# "critical" data is created, an etcd snapshot is taken (the correct
# moment to take one — BEFORE anything goes wrong), and then the
# ConfigMap is "accidentally" deleted to simulate an operator mistake.
# Your task: restore the ConfigMap using the etcd snapshot, following the
# standard etcd restore procedure (see Q14 in the CKA/CKAD/CKS scenario
# doc): snapshot restore to a NEW data directory, then repoint the etcd
# static pod manifest at it. This is the single most tested CKA
# disaster-recovery scenario — worth doing slowly and deliberately.
echo "==> [app-5] Creating critical ConfigMap, taking an etcd snapshot, then deleting it..."
kubectl create configmap critical-data -n "${NS}" \
  --from-literal=note="do not lose this - restore me from the etcd snapshot" \
  --dry-run=client -o yaml | kubectl apply -f -

ETCD_CID=$(docker exec "${CP_NODE}" crictl ps --name etcd -q 2>/dev/null | head -1 || true)
if [ -n "${ETCD_CID}" ]; then
  docker exec "${CP_NODE}" crictl exec "${ETCD_CID}" sh -c \
    "ETCDCTL_API=3 etcdctl snapshot save /var/lib/etcd/day6-snapshot.db \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key" \
    && echo "==> [app-5] Snapshot saved to /var/lib/etcd/day6-snapshot.db inside ${CP_NODE}." \
    || echo "==> [app-5] WARNING: automated snapshot failed — take it manually before continuing (see README day6 section for the exact commands)."
else
  echo "==> [app-5] WARNING: couldn't locate the etcd container via crictl — take the snapshot manually before continuing (see README day6 section)."
fi

sleep 2
kubectl delete configmap critical-data -n "${NS}"
echo "==> [app-5] critical-data ConfigMap deleted — restore it from the snapshot."

echo ""
echo "==> Done. Day 6 issues created."
echo "==> app-1/app-2 affect the WHOLE cluster's scheduling/reconciliation, not just namespace ${NS}."
echo "==> Start with: kubectl get pods -A ; kubectl get nodes"
