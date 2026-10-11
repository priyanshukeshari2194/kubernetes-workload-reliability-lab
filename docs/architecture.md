# Architecture: kubernetes-workload-reliability-lab

> **Audience:** KubeCon presentation slide notes — assumes familiarity with containers but not Kubernetes internals.  
> **Honesty note:** This lab runs on a single-node `kind` cluster. It is a learning tool, not a production-ready reference.

---

## Object Stack

```
┌──────────────────────────────────────────────────────────────────────┐
│  Deployment (desired state declaration + rollout strategy)           │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  ReplicaSet (owns + reconciles N identical Pods)               │  │
│  │  ┌──────────────────┐  ┌──────────────────┐                   │  │
│  │  │  Pod             │  │  Pod             │  ...              │  │
│  │  │ ┌──────────────┐ │  │ ┌──────────────┐ │                   │  │
│  │  │ │ App Container│ │  │ │ App Container│ │                   │  │
│  │  │ └──────────────┘ │  │ └──────────────┘ │                   │  │
│  │  └──────────────────┘  └──────────────────┘                   │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
         │ Pod IPs registered/deregistered by
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Endpoints object  ←──── Endpoints controller (kube-controller-mgr) │
│  { addresses: [{ip: 10.244.x.x}, ...], notReadyAddresses: [...] }   │
└──────────────────────────────────────────────────────────────────────┘
         │ Service selects from Endpoints
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Service (ClusterIP / NodePort)                                      │
│  Stable DNS name + VIP → kube-proxy programs iptables/ipvs rules    │
└──────────────────────────────────────────────────────────────────────┘
         │
         ▼ External / Port-forward traffic
   [ Client / kubectl port-forward ]
```

---

## Each Object and WHY It Exists

### App Container
The OCI-compliant process image. Exists to run the actual workload. On its own, a container has no self-healing, scaling, or discovery capabilities — it is just a process.

### Pod
The smallest schedulable unit in Kubernetes. A Pod wraps one or more containers with shared network namespace (same IP) and optionally shared storage volumes. **Why a Pod and not just a container?** The Pod abstraction lets Kubernetes inject sidecars (logging, service-mesh proxies), share a loopback interface between containers, and attach metadata (labels, annotations) that drive the higher-level controllers.

### ReplicaSet
A controller that watches for Pods matching its `selector` and reconciles toward `replicas: N`. If a Pod disappears (node eviction, OOMKill, manual delete), the ReplicaSet creates a replacement. **Why not use a ReplicaSet directly?** You can, but ReplicaSets are not designed to own a rollout strategy — they just enforce a count. Deployments manage ReplicaSets to enable rolling updates with zero-downtime guarantees.

### Deployment
Owns the desired rollout strategy (`RollingUpdate`, `Recreate`) and revision history. When you update an image tag, the Deployment controller creates a new ReplicaSet and scales it up while scaling the old one down, respecting `maxUnavailable` and `maxSurge`. **Why it exists:** Decouples "I want 3 replicas of this app" from "I want to safely migrate from image v1 to v2." The old ReplicaSet is retained (up to `revisionHistoryLimit`) to enable `kubectl rollout undo`.

### Service
A stable virtual IP (ClusterIP) and DNS name backed by `kube-proxy` rules (iptables or ipvs). Because Pod IPs are ephemeral — they change on every restart — clients need a stable address. The Service provides that stable front door and load-distributes across all *ready* Pod IPs. **Why it exists:** Pod IPs are not durable. The Service abstracts the ephemeral Pod network from the consumer.

### Endpoints (and EndpointSlice) Controller
A controller inside `kube-controller-manager` that watches Pods with matching labels and populates the `Endpoints` object with IPs of Pods that are currently **Ready**. `kube-proxy` programs forwarding rules from those IPs. If a Pod fails its readiness probe, its IP is moved to `notReadyAddresses` and `kube-proxy` stops routing traffic to it. **Why it exists:** The Endpoints controller is the bridge between the "what Pods exist" world and the "what traffic destinations are valid" world.

---

## How Probes Interact with the Endpoints Object and Service Routing

Kubernetes supports three probe types evaluated by the `kubelet` on each node:

| Probe | Failure consequence | Recovery |
|---|---|---|
| **Startup** | Container is killed and restarted (blocks liveness/readiness evaluation until passing) | Restart |
| **Liveness** | Container is killed and restarted | Restart |
| **Readiness** | Pod IP is moved to `notReadyAddresses` in the Endpoints object — traffic stops | Probe passes → IP restored |

**Key insight:** A readiness probe failure does **not** restart the container. The Pod continues running but receives zero traffic. This is the correct behaviour for a temporarily overloaded or warming-up service. Liveness is the blunter instrument: if the process is truly hung, liveness kills it.

**Flow during a readiness failure:**
```
kubelet runs HTTP GET /healthz → 503
  → Pod condition Ready=False
    → Endpoints controller removes Pod IP from addresses[]
      → kube-proxy removes iptables rule
        → Service stops routing to that Pod
```

**Flow during recovery:**
```
kubelet runs HTTP GET /healthz → 200
  → Pod condition Ready=True
    → Endpoints controller adds Pod IP back to addresses[]
      → kube-proxy re-adds iptables rule
        → Service resumes routing to that Pod
```

---

## Security Layers

### Pod Security Admission (PSA)
Applied at the namespace level via a label (`pod-security.kubernetes.io/enforce: baseline`). The `baseline` policy prevents the most critical privilege-escalation vectors: `privileged: true`, `hostPID`, `hostNetwork`, `hostPath` volumes, and running as UID 0 without explicit opt-in. PSA is an admission webhook built into the API server — it rejects non-compliant Pod specs at creation time.

**What `baseline` does NOT prevent:** running as a non-root UID with write access to the container filesystem, binding to ports above 1024, or use of `capabilities` beyond the restricted list.

### SecurityContext
Applied at the Pod and container level. In this lab:
- `runAsNonRoot: true` — the container process must not run as UID 0.
- `runAsUser: 1000` — explicit UID for the process.
- `readOnlyRootFilesystem: true` — the container's root filesystem is mounted read-only. This prevents an attacker who achieves code execution from writing malware to disk, installing tools, or modifying application binaries. It does **not** prevent writes to explicitly mounted volumes or `emptyDir` mounts.
- `allowPrivilegeEscalation: false` — the process cannot gain more privileges than its parent (disables `setuid` binaries).
- `seccompProfile: RuntimeDefault` — applies the container runtime's default seccomp filter, which blocks a substantial set of syscalls not needed by typical applications (e.g., `ptrace`, `reboot`, raw socket creation).

### ServiceAccount
Each Pod is assigned a ServiceAccount. By default, Kubernetes mounts a ServiceAccount token into every Pod at `/var/run/secrets/kubernetes.io/serviceaccount/`. In this lab, `automountServiceAccountToken: false` is set because the application does not need to call the Kubernetes API. Leaving the token mounted is a common supply-chain attack vector: a compromised container can use the token to enumerate cluster resources.

### ResourceQuota
Applied at the namespace level. Enforces upper bounds on total CPU requests/limits, memory requests/limits, and object counts (Pods, Services, Secrets, etc.) within the namespace. **What it prevents:** a single namespace consuming unbounded cluster resources, preventing noisy-neighbour starvation of other workloads. **What it does NOT prevent:** a Pod within quota from consuming its full CPU limit and starving other Pods on the same node (that is the job of the Linux CFS scheduler and cgroup limits, not Kubernetes quota).

---

## Control-Plane Behaviour During Each Failure Scenario

### Scenario A — Readiness Probe Failure

1. `kubelet` runs the readiness probe HTTP check and receives a non-2xx response (or connection refused).
2. `kubelet` sets `Pod.status.conditions[Ready]=False`.
3. The **Endpoints controller** (running in `kube-controller-manager`) watches Pod status. It detects `Ready=False` and moves the Pod IP from `addresses[]` to `notReadyAddresses[]` in the `Endpoints` object.
4. `kube-proxy` (on each node) watches the `Endpoints` object and removes the corresponding iptables/ipvs rule. Traffic to the Service VIP no longer reaches this Pod.
5. No restart occurs. The Pod continues running.
6. When the probe recovers, steps 2–4 reverse. The Pod IP is returned to `addresses[]` and traffic resumes.

### Scenario B — OOMKilled / CrashLoopBackOff

1. The container's memory usage exceeds the `resources.limits.memory` value.
2. The Linux kernel OOM killer sends `SIGKILL` (signal 9) to the container's PID 1. This is a kernel-level action — Kubernetes does not send the kill; the cgroup memory controller triggers it.
3. The container exits with **exit code 137** (128 + 9).
4. `kubelet` detects the container exit, records `Reason: OOMKilled` in the Pod's `lastState`, and restarts the container.
5. If the container keeps crashing, `kubelet` applies exponential back-off (10s → 20s → 40s → … up to 5 minutes) and the Pod status transitions to `CrashLoopBackOff`.
6. The Pod remains in the `Running` phase during CrashLoopBackOff (the Pod object exists and is scheduled), but the container is repeatedly failing. Readiness probe will also fail, so the Endpoints controller removes the Pod from service.

### Scenario C — Bad Image / Stuck Rollout

1. A Deployment update is applied with an image that does not exist in the kind cluster's local cache (`imagePullPolicy: Never`).
2. The Deployment controller creates a new ReplicaSet for the new image and begins scaling it up.
3. `kubelet` attempts to pull the image, gets `ErrImageNeverPull` (because `imagePullPolicy: Never` and the image is not present locally), and the new Pod enters `ImagePullBackOff` / `ErrImageNeverPull` state.
4. The new Pod never becomes Ready. The Deployment controller respects `maxUnavailable: 0`, so it does not scale down the old ReplicaSet. The old Pods remain up and serving traffic.
5. The rollout is **stuck but not destructive**: old Pods are still healthy, new Pods never start. `kubectl rollout status` hangs indefinitely.
6. `kubectl rollout undo` instructs the Deployment controller to set the pod template back to the previous revision's spec. The new (bad) ReplicaSet scales to 0 and the old ReplicaSet scales back to the desired replica count.

---

## What This Lab Does NOT Demonstrate

This section is intentionally explicit. Omitting these caveats from a conference talk is a form of misinformation.

| Topic | Why it is absent |
|---|---|
| **NetworkPolicy enforcement** | `kind` clusters do not ship with a CNI plugin that enforces NetworkPolicy by default (kindnet does not). Applying NetworkPolicy manifests will appear to succeed but have no effect. |
| **etcd encryption at rest** | Requires `EncryptionConfiguration` passed to `kube-apiserver`. This lab does not configure the kind control-plane with custom API server flags. |
| **RBAC beyond ServiceAccount token mount** | There are no RoleBindings or ClusterRoleBindings configured. The `automountServiceAccountToken: false` setting is demonstrated, but actual RBAC policy design — least-privilege roles, audit logging of API calls — is not. |
| **Multi-node scheduling and topology** | `kind` defaults to a single-node cluster. Pod anti-affinity, topology spread constraints, and node drain scenarios require a multi-node setup. |
| **Horizontal Pod Autoscaler (HPA)** | HPA requires `metrics-server` and a working metrics pipeline. This lab does not configure metrics-server. |
| **PodDisruptionBudget (PDB) enforcement** | PDBs interact with the eviction API during node drains. Single-node kind clusters cannot demonstrate this realistically. |
| **Secret encryption** | Kubernetes Secrets are base64-encoded, not encrypted, by default. This lab does not configure envelope encryption. |
| **Persistent storage failure modes** | All workloads use ephemeral storage. PVC binding, storage class provisioning, and volume mount failures are not covered. |
| **Admission webhooks (custom)** | PSA is a built-in admission controller. Custom mutating/validating webhooks (e.g., OPA Gatekeeper, Kyverno) are not deployed. |
| **Service mesh / mTLS** | No Istio, Linkerd, or Cilium. Pod-to-pod traffic is unencrypted on the cluster network. |

---

*Last updated: 2026-10-11*
