# Limitations, Scope, and Interview Preparation

## kubernetes-workload-reliability-lab

---

## 1. What This Lab Does NOT Demonstrate or Guarantee

| Claim | Reality |
|---|---|
| Production-ready security posture | This lab uses `baseline` PSA and a basic SecurityContext. It does not configure network policies, Secret encryption, audit logging, or image signing. |
| Multi-node failure scenarios | The default kind configuration is a single node. Node failure, pod eviction, anti-affinity, and topology spread constraints cannot be meaningfully demonstrated. |
| NetworkPolicy enforcement | `kindnet` (kind's default CNI) does not enforce NetworkPolicy. Manifests will be accepted by the API server but have zero effect. |
| etcd encryption at rest | Not configured. Secrets are stored as base64 in etcd. |
| Real RBAC design | `automountServiceAccountToken: false` is demonstrated, but no Roles, ClusterRoles, RoleBindings, or ClusterRoleBindings are authored. |
| HPA / autoscaling | No metrics-server, no HPA objects. |
| PodDisruptionBudget behaviour | PDB enforcement requires the eviction API and multi-node cluster to be meaningful. |
| Service mesh / mTLS | No Istio, Linkerd, or Cilium. Pod-to-pod traffic is unencrypted. |
| Persistent volume failure modes | All workloads use ephemeral storage only. |
| Admission webhooks (custom) | No OPA Gatekeeper or Kyverno. |
| Image signing / provenance | No Cosign, Notary, or ImagePolicyWebhook. |
| CI/CD pipeline integration | No GitHub Actions, Tekton, or ArgoCD. The lab is applied manually. |

---

## 2. What Is Implemented vs. What Remains Experimental

### Implemented and Verifiable

- [x] Deployment with rolling update strategy (`maxUnavailable: 0`, `maxSurge: 1`)
- [x] ReplicaSet reconciliation (delete a Pod manually, observe replacement)
- [x] HTTP readiness probe → Endpoints controller → Service routing (Scenario A)
- [x] Memory limit enforcement → OOMKilled exit 137 → CrashLoopBackOff (Scenario B)
- [x] `imagePullPolicy: Never` with missing image → `ErrImageNeverPull` → stuck rollout (Scenario C)
- [x] `kubectl rollout undo` restoring the previous ReplicaSet
- [x] `revisionHistoryLimit` controlling how many old ReplicaSets are retained
- [x] `automountServiceAccountToken: false` on the Pod spec
- [x] `readOnlyRootFilesystem: true` in SecurityContext
- [x] `runAsNonRoot: true` and explicit `runAsUser`
- [x] `allowPrivilegeEscalation: false`
- [x] `seccompProfile: RuntimeDefault`
- [x] ResourceQuota at the namespace level
- [x] Pod Security Admission `baseline` enforcement on the namespace

### Not Verified in This Environment

> These manifests are authored correctly but were not executed against a live cluster during authoring because the Docker daemon was not running in the authoring environment.

- [ ] Actual `kubectl get endpoints` outputs during Scenario A
- [ ] Actual `kubectl top pods` output during Scenario B (also requires metrics-server)
- [ ] Actual `kubectl rollout history` output with populated `CHANGE-CAUSE`
- [ ] PSA rejection of a deliberately non-compliant Pod spec
- [ ] ResourceQuota `exceeded` error on actual resource exhaustion

---

## 3. What Would Still Be Required for Real Production Use

1. **Multi-node cluster** (at minimum 3 control-plane nodes for HA etcd) on real infrastructure or a managed service (GKE, EKS, AKS).
2. **etcd encryption at rest** via `EncryptionConfiguration` with a KMS provider.
3. **NetworkPolicy** with an enforcing CNI (Calico, Cilium, Antrea).
4. **RBAC** with least-privilege Roles scoped to each ServiceAccount.
5. **Image signing and verification** (Cosign + ImagePolicyWebhook or Kyverno policy).
6. **Audit logging** configured on the API server.
7. **PodDisruptionBudgets** for every stateful or critical workload.
8. **HPA** with appropriate CPU/memory metrics and custom metrics where relevant.
9. **Persistent storage** with appropriate StorageClass, backup, and failure testing.
10. **Service mesh** for mTLS between services, traffic management, and observability.
11. **Secrets management** via an external store (Vault, AWS Secrets Manager) with CSI driver or ESO, not Kubernetes Secrets alone.
12. **Admission webhooks** (Kyverno or OPA Gatekeeper) to enforce policy at scale.
13. **CI/CD pipeline** with image build, scan, sign, load-test, and progressive delivery gates.
14. **Observability** stack: Prometheus, Grafana, alerting rules, and distributed tracing.

---

## 4. Pre-Conference Verification Checklist

> The author must personally verify each item before presenting this lab at a conference talk. Claiming behaviour you have not observed is a form of misinformation.

- [ ] Run `kind create cluster` from scratch and confirm the cluster comes up cleanly.
- [ ] Apply all manifests in order and confirm no errors from `kubectl apply`.
- [ ] Verify PSA blocks a deliberately privileged Pod (e.g., `privileged: true`) in the namespace.
- [ ] Execute Scenario A end-to-end: trigger probe failure, observe `kubectl get endpoints` showing `<none>`, restore probe, observe endpoints returning.
- [ ] Execute Scenario B end-to-end: observe `OOMKilled` in `kubectl describe pod`, see exit code 137 in `lastState`.
- [ ] Execute Scenario C end-to-end: apply bad image, observe `ErrImageNeverPull`, confirm old Pods still serving, run `kubectl rollout undo`, confirm recovery.
- [ ] Run `kubectl rollout history` and confirm `CHANGE-CAUSE` is populated (requires `--record` flag or manual annotation — verify which mechanism works on your cluster version).
- [ ] Confirm `automountServiceAccountToken: false` by exec-ing into the Pod and verifying `/var/run/secrets/kubernetes.io/serviceaccount/` does not exist.
- [ ] Confirm `readOnlyRootFilesystem: true` by exec-ing into the Pod and attempting to write to `/tmp` (should fail) vs. a mounted `emptyDir` (should succeed).
- [ ] Run ResourceQuota test: attempt to create more Pods than the quota allows and observe the `forbidden: exceeded quota` error.
- [ ] If claiming `kubectl top pods`, install metrics-server first and verify it works.
- [ ] If showing any `kubectl top` or HPA output in slides, label it "with metrics-server installed" explicitly.
- [ ] Time the 30-minute demo runbook at least once before the talk.

---

## 5. Technical Interview Questions and Accurate Answers

### Q1: What is the difference between readiness, liveness, and startup probes?

**Answer:**

- **Startup probe:** Evaluated first, before liveness or readiness. If it fails repeatedly (beyond `failureThreshold`), the container is killed and restarted. Its purpose is to give slow-starting containers enough time to initialise without being killed by liveness. Once it succeeds once, it is never evaluated again.
- **Liveness probe:** Evaluated continuously after startup. Failure causes the container to be **killed and restarted** by kubelet. Use it to detect hung processes (e.g., deadlock) that are still running but not making progress.
- **Readiness probe:** Evaluated continuously. Failure causes the Pod's IP to be **removed from the Endpoints object**, stopping Service traffic. The container is NOT restarted. Use it to signal "I am temporarily not ready to serve traffic" (e.g., warming up a cache, waiting for a downstream dependency).

Key distinction: liveness = "is the process alive enough to be worth keeping?"; readiness = "is the process ready to receive traffic right now?"

---

### Q2: What does OOMKilled exit code 137 mean, and why that number?

**Answer:**

Exit code **137** = 128 + 9.

Linux encodes process termination by signal as `128 + signal_number`. Signal 9 is `SIGKILL`. The Linux kernel's OOM (Out Of Memory) killer sends `SIGKILL` to the process when its cgroup memory limit is exceeded. Because SIGKILL cannot be caught or ignored by the process, the exit code is always 137.

Kubernetes reads this exit code from the container runtime, records `Reason: OOMKilled` in `pod.status.containerStatuses[].lastState`, and increments the restart counter. The restart back-off (CrashLoopBackOff) still applies even to OOMKills.

---

### Q3: What does `maxUnavailable: 0` + `maxSurge: 1` mean during a rolling update?

**Answer:**

- `maxUnavailable: 0` — at no point during the rollout may the number of *available* (Ready) Pods fall below the desired replica count. The old ReplicaSet is not scaled down until a new Pod is Ready.
- `maxSurge: 1` — the total number of Pods (old + new) may exceed the desired count by at most 1 during the transition.

**Net effect:** The rollout proceeds strictly one Pod at a time. One new Pod is created (surge +1), and only after it becomes Ready is one old Pod terminated (unavailable still 0). This is the safest rolling update strategy but is the slowest and requires the cluster to have spare capacity for the surge Pod. It also means that if no new Pod ever becomes Ready (e.g., bad image), the old Pods are never terminated — the rollout stalls but does not break production.

---

### Q4: Why do we disable `automountServiceAccountToken`?

**Answer:**

By default, Kubernetes mounts a ServiceAccount token into every Pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. This token is a JWT that can be used to authenticate to the Kubernetes API server.

If an attacker achieves code execution in a container (e.g., via a dependency vulnerability), they immediately have a credential that can call the Kubernetes API. The default ServiceAccount in a namespace often has more permissions than expected (and RBAC is frequently misconfigured in practice).

Setting `automountServiceAccountToken: false` removes this automatic token mount. If the application genuinely needs to call the Kubernetes API (e.g., an operator or custom controller), the token can be mounted explicitly via a projected volume with a bounded audience and TTL — which is more secure than the long-lived default token.

---

### Q5: What does `readOnlyRootFilesystem: true` protect against, and what does it NOT protect against?

**Answer:**

**Protects against:**
- An attacker writing malware, scripts, or modified binaries to the container's root filesystem.
- Supply-chain attacks that attempt to install tools (curl, wget, nc) after initial code execution.
- Accidentally writing logs or temporary files to the root filesystem (which would be lost on Pod restart anyway).

**Does NOT protect against:**
- Writes to explicitly mounted volumes (`emptyDir`, PVC mounts, ConfigMap mounts where the volume is writable).
- Network-based attacks (exfiltration, reverse shells via existing binaries).
- In-memory attacks (the container's memory is still writable).
- An attacker who can read sensitive environment variables or mounted Secrets.
- Privilege escalation via existing `setuid` binaries already present in the image (mitigate with `allowPrivilegeEscalation: false`).

---

### Q6: What does a ResourceQuota prevent vs. what does it NOT prevent?

**Answer:**

**Prevents (within the namespace):**
- Creating more Pods, Services, Secrets, ConfigMaps, or PVCs than the quota allows.
- Consuming more total CPU requests/limits or memory requests/limits than the quota allows.
- Protects other namespaces from a single namespace's unbounded resource consumption.

**Does NOT prevent:**
- A Pod within quota from using its full CPU limit and starving other Pods *on the same node* (that is enforced by cgroup CFS quotas, not Kubernetes quota).
- A Pod from consuming more memory than its request (up to its limit — or until OOMKilled).
- Resource usage within a container that doesn't go through the Kubernetes scheduler (e.g., a process fork-bombing inside its CPU limit).
- Cross-namespace resource consumption impacts (quota is namespace-scoped).

---

### Q7: Why is base64 in a Kubernetes Secret not encryption?

**Answer:**

Base64 is an encoding scheme, not a cryptographic operation. It has no key, no confidentiality, and no integrity guarantee. Anyone with read access to the Secret object (via `kubectl get secret -o yaml`, the etcd data directory, or the API server's audit log) can trivially decode it with `base64 -d`.

Kubernetes Secrets are base64-encoded to handle binary data safely in JSON/YAML — not for security. The actual security of Secrets depends on:
1. **RBAC** — restricting who can `get`/`list` Secrets.
2. **etcd encryption at rest** — using `EncryptionConfiguration` with a KMS provider.
3. **External secret stores** — injecting secrets at runtime from Vault, AWS Secrets Manager, etc., so the plaintext never enters etcd.

Saying "we use Kubernetes Secrets" without these controls is a false sense of security.

---

### Q8: What does `revisionHistoryLimit` control?

**Answer:**

`revisionHistoryLimit` (default: 10) controls how many old ReplicaSets the Deployment controller retains after a rollout. Old ReplicaSets are scaled to 0 (no Pods running) but the ReplicaSet objects remain in the cluster.

**Why it matters:**
- Each retained ReplicaSet enables `kubectl rollout undo` to a specific revision (`--to-revision=N`).
- Setting it to 0 saves etcd space but removes rollback capability entirely.
- Setting it too high in a cluster with many frequently-updated Deployments can accumulate thousands of empty ReplicaSet objects.

**Important:** `revisionHistoryLimit` controls the number of *old* ReplicaSets retained, not including the currently active one.

---

### Q9: What can `kubectl rollout undo` NOT reverse?

**Answer:**

`kubectl rollout undo` reverts the Pod template spec (image, environment variables, resource limits, etc.) to the previous revision. It does NOT reverse:

- **ConfigMap or Secret content changes.** If you changed the data in a ConfigMap that is referenced by the Deployment's envFrom, `rollout undo` does not restore the ConfigMap's old data.
- **Database schema migrations.** If the new image ran `db migrate` on startup, the schema is changed. Rolling back the image does not roll back the schema.
- **Persistent volume data.** Any data written by the new version is not undone.
- **Changes to other Kubernetes objects** (Services, Ingresses, other Deployments) that were applied alongside the Deployment update.
- **Annotations applied directly to the Deployment** (not part of the pod template).

---

### Q10: Why do we use `imagePullPolicy: Never` in the kind lab?

**Answer:**

`kind` clusters run inside Docker containers. The container runtime inside kind (containerd) does not share the Docker image cache on the host. If you build an image with `docker build` on your host, kind cannot see it.

`kind load docker-image <image>:<tag>` explicitly copies the image from the host Docker daemon into kind's containerd store. After loading, `imagePullPolicy: Never` tells kubelet: "never attempt to pull this image from a registry; use only what is already present locally." This prevents kubelet from trying to reach Docker Hub (which would fail or pull a different version) and ensures the locally built image is used.

In a real cluster with a registry, you would use `IfNotPresent` (use local cache if available, otherwise pull) or `Always` (always pull to ensure the latest digest).

---

### Q11: What does the Endpoints controller do?

**Answer:**

The Endpoints controller is a control loop running inside `kube-controller-manager`. It watches:
1. **Services** with a label selector.
2. **Pods** with matching labels.
3. **Pod readiness status** (`Ready` condition).

For each Service, it maintains an `Endpoints` object (same name, same namespace) whose `addresses[]` list contains the IPs of Pods that match the Service's selector AND are currently Ready. Pods that match the selector but are NotReady are placed in `notReadyAddresses[]`.

`kube-proxy` on each node watches `Endpoints` objects and programs iptables/ipvs rules accordingly. This is the chain that connects "a Pod passed its readiness probe" to "traffic is forwarded to that Pod."

In Kubernetes 1.21+, the newer `EndpointSlice` controller performs the same role but uses `EndpointSlice` objects, which scale better for large Services (many Pods).

---

### Q12: What is the difference between a Pod being NotReady vs. being in CrashLoopBackOff?

**Answer:**

| | NotReady | CrashLoopBackOff |
|---|---|---|
| **Pod phase** | Running | Running |
| **Container state** | Running (process is up) | Waiting (in back-off between restarts) |
| **Readiness** | Ready=False | Ready=False |
| **Restart count** | Does not increase | Increases with each crash |
| **Traffic from Service** | Stopped (removed from Endpoints) | Stopped (removed from Endpoints) |
| **Root cause** | Readiness probe failing (process still running) | Container keeps exiting (crash, OOMKill, config error) |
| **Recovery action** | Fix what the readiness probe checks; no restart needed | Fix the crash cause; may require image change or config fix |

NotReady is the *healthy* graceful state — the pod is running but not yet accepting traffic. CrashLoopBackOff means the container cannot stay alive at all.

---

### Q13: What happens if you set `maxUnavailable: 1` with 2 replicas and a bad image?

**Answer:**

With `maxUnavailable: 1` and 2 desired replicas, the Deployment is allowed to have 1 unavailable Pod during the rollout (minimum available = 1).

**Scenario with a bad image:**
1. The Deployment controller creates 1 new Pod with the bad image (because `maxSurge` allows it, or it scales down an old one first depending on configuration).
2. The new Pod fails to start (`ErrImageNeverPull`, `ImagePullBackOff`, or crashes immediately).
3. The Deployment controller, having already counted 1 unavailable (the new Pod), may then **scale down one of the old Pods** — bringing healthy capacity to just 1 out of 2.
4. You are now running **half capacity with a bad rollout in progress** and your service is degraded.

This is why `maxUnavailable: 0` is the safer default when availability is critical. `maxUnavailable: 1` is appropriate only when you are willing to tolerate temporary degraded capacity in exchange for a faster rollout.

---

### Q14: What does `seccompProfile: RuntimeDefault` do?

**Answer:**

Seccomp (Secure Computing Mode) is a Linux kernel feature that filters which syscalls a process is allowed to make. `RuntimeDefault` applies the container runtime's built-in seccomp profile (defined by containerd or Docker), which blocks a significant set of syscalls that typical applications do not need but attackers commonly use:

Examples of blocked syscalls under `RuntimeDefault`:
- `ptrace` (used for debugging/code injection between processes)
- `reboot`, `mount`, `swapon` (privileged system operations)
- `keyctl`, `add_key` (kernel keyring manipulation)
- Various raw socket and network operations

**What it does NOT prevent:**
- Syscalls used by normal application code (read, write, open, socket, etc.) — these are allowed.
- Attacks that don't require unusual syscalls.
- Attacks within the set of allowed syscalls (e.g., exploiting a logic bug in a web framework).

`RuntimeDefault` is a low-risk baseline. The more targeted `Localhost` profile (a custom JSON file) offers stronger guarantees but requires profiling the application's actual syscall usage.

---

### Q15: Why don't ConfigMap changes auto-reload when using `envFrom`?

**Answer:**

When you use `envFrom` (or `env.valueFrom.configMapKeyRef`) in a Pod spec, the ConfigMap values are injected as environment variables into the container **at container start time**. Environment variables in a Unix process are inherited at `exec()` time and are immutable for the lifetime of the process — the kernel does not provide a mechanism to update environment variables in a running process from outside.

Therefore:
- If you `kubectl edit configmap` and change a value, running containers see the old value.
- A **Pod restart** is required to pick up the new environment variable values.

**Contrast with volume mounts:** If you mount a ConfigMap as a file (via `volumes[].configMap`), Kubernetes periodically syncs the mounted files to match the ConfigMap's current content (default sync period: ~60 seconds). The application must actively re-read the file to notice the change — Kubernetes does not send a signal to the process.

For hot-reload, patterns include: watching the mounted file and re-reading it, using a sidecar that sends a reload signal (SIGHUP), or using a framework-level reload mechanism.

---

### Q16: What is the difference between `requests` and `limits` for CPU vs. memory?

**Answer:**

**CPU:**
- `requests`: the amount of CPU the scheduler uses to decide where to place the Pod. It is the *guaranteed minimum* the container will receive under contention via CFS (Completely Fair Scheduler) time-slicing.
- `limits`: the maximum CPU time the container can consume. If the container tries to use more, the Linux CFS scheduler **throttles** it (adds wait time). The process is NOT killed. The container continues running at a reduced CPU rate.

**Memory:**
- `requests`: used by the scheduler for placement decisions. Kubernetes treats memory requests as a soft reservation.
- `limits`: the maximum memory the container's cgroup can use. If exceeded, the Linux OOM killer **kills** the container (exit 137). Unlike CPU, you cannot throttle memory usage — you can only deny allocation once the limit is hit.

**Key asymmetry:** CPU over-limit = throttled (process slows but survives). Memory over-limit = OOMKilled (process is killed). This is why memory limit tuning is more dangerous than CPU limit tuning.

---

### Q17: What does Pod Security Admission `baseline` policy prevent?

**Answer:**

The `baseline` policy prevents the most obviously dangerous privilege configurations while remaining compatible with most containerised workloads. It blocks:

- `spec.hostPID: true`, `spec.hostIPC: true` (host process namespace access)
- `spec.hostNetwork: true` (host network namespace access)
- `spec.volumes[].hostPath` (mounting host filesystem paths)
- `spec.containers[].securityContext.privileged: true`
- `spec.containers[].securityContext.capabilities.add` of dangerous capabilities (`SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, etc.)
- `spec.containers[].securityContext.allowPrivilegeEscalation: true` (when explicitly set)
- AppArmor profiles other than `RuntimeDefault` or `Localhost`
- `/proc` mount type `Unmasked`

**What `baseline` does NOT prevent (unlike `restricted`):**
- Running as root (UID 0) — `restricted` requires `runAsNonRoot: true`
- Writable root filesystem — `restricted` requires `readOnlyRootFilesystem: true`
- `seccompProfile` not set — `restricted` requires a seccomp profile

---

### Q18: Why does kind use `imagePullPolicy: Never` vs. `IfNotPresent`?

**Answer:**

`IfNotPresent` instructs kubelet to use the local image cache if the image is already present, and pull from a registry if not. In a kind cluster, the "local cache" is containerd's image store inside the kind node container — **not** the host Docker image cache.

If you build `app:v1` with `docker build` on your host, that image is in Docker's image store. It is **not** automatically in kind's containerd store. With `IfNotPresent`, kubelet would not find `app:v1` in containerd (cache miss), attempt to pull it from Docker Hub, and fail with `ImagePullBackOff` (no such image on the public registry).

With `Never`, kubelet does not attempt a pull at all. It either finds the image in containerd (because you ran `kind load docker-image app:v1`) or fails with `ErrImageNeverPull`. This makes the failure mode explicit and deterministic — it is never ambiguous whether you are running the image you built or something pulled from a registry.

---

### Q19: What is the `change-cause` annotation used for?

**Answer:**

The `kubernetes.io/change-cause` annotation on a Deployment stores a human-readable description of why a rollout was made. It is displayed in `kubectl rollout history`:

```
REVISION  CHANGE-CAUSE
1         initial deployment
2         bump app image to v2 for memory leak fix
3         revert to v1 pending investigation
```

**How it is set:**
- Legacy (deprecated): `kubectl apply -f ... --record` automatically wrote the full `kubectl` command as the annotation.
- Current practice: set it manually in the manifest or with `kubectl annotate deployment/<name> kubernetes.io/change-cause="your message"`.

**What it does NOT do:**
- It is purely informational. It has no effect on rollout behaviour.
- `kubectl rollout undo` does not use or update it.
- It is not cryptographically signed — anyone with write access to the Deployment can change it.

---

### Q20: How does Service endpoint selection work with label selectors?

**Answer:**

A Service with a `selector` field (e.g., `app: my-app`) instructs the Endpoints controller to continuously watch all Pods in the same namespace. For each Pod:

1. **Label match:** Does the Pod have all labels specified in the Service's selector? (The Pod may have additional labels; the selector only requires the specified keys to match.)
2. **Ready check:** Is the Pod's `Ready` condition `True`? (All containers passing their readiness probes, or no readiness probe defined.)
3. **Not terminating:** Is the Pod not in a `Terminating` state? (Pods being deleted are removed from Endpoints immediately on deletion, before the container actually stops, to drain traffic first — this is part of the graceful termination sequence.)

If all three conditions are true, the Pod's IP and container port are added to `Endpoints.subsets[].addresses[]`. Otherwise, if labels match but the Pod is not ready, it goes to `notReadyAddresses[]`. If labels don't match, the Pod is ignored entirely.

**Important nuance:** The label selector is evaluated against Pod labels at each sync cycle. If you change a Pod's labels (removing a selector label), it is immediately de-selected from the Service — useful for taking a single Pod out of rotation for debugging without deleting it.

---

## 6. Demo Runbook: 30-Minute Technical Presentation

> Pre-requisites: kind cluster running, all manifests applied, `kubectl port-forward svc/app 8080:80 -n reliability-lab` running in a separate terminal.

### Minutes 0–5: Setup and Context (5 min)

- Show the architecture diagram (from `docs/architecture.md`).
- Briefly explain the object stack: Container → Pod → ReplicaSet → Deployment → Endpoints → Service.
- Show the running cluster: `kubectl get all -n reliability-lab`
- Show the SecurityContext and ResourceQuota: `kubectl describe namespace reliability-lab`

### Minutes 5–15: Scenario A — Readiness Probe Failure (10 min)

- **Explain** readiness vs. liveness probes (1 min).
- **Trigger** failure: exec into the Pod and disable the healthcheck endpoint.
- **Watch** in real time: `kubectl get pods -n reliability-lab -w` (split terminal).
- **Show** the Endpoints object draining: `kubectl get endpoints -n reliability-lab`.
- **Describe** the Pod: `kubectl describe pod` → show `Readiness probe failed` events.
- **Demo** Service refuses traffic: `curl localhost:8080` → connection error.
- **Recover**: re-enable the healthcheck.
- **Show** Endpoints object refilling: `kubectl get endpoints -n reliability-lab`.
- **Key message**: The Pod was never restarted. Traffic was stopped at the routing layer.

### Minutes 15–22: Scenario B — OOMKilled (7 min)

- **Explain** memory limits, cgroup enforcement, OOMKill (1 min).
- **Apply** a low memory limit: `kubectl set resources deployment/app -n reliability-lab --limits=memory=10Mi`
- **Watch**: `kubectl get pods -n reliability-lab -w` → show OOMKilled → CrashLoopBackOff.
- **Describe** pod: `kubectl describe pod` → show `Exit Code: 137`, `Reason: OOMKilled`, `Last State: Terminated`.
- **Key message**: Exit 137 = 128 + SIGKILL. The kernel killed it, not Kubernetes.
- **Recover**: restore the memory limit to a sensible value.

### Minutes 22–29: Scenario C — Stuck Rollout (7 min)

- **Explain** rolling update strategy, `maxUnavailable: 0` (1 min).
- **Apply** a bad image: `kubectl set image deployment/app -n reliability-lab app=app:v-does-not-exist`
- **Show** rollout stalling: `kubectl rollout status deployment/app -n reliability-lab` (hangs).
- **Show** old Pods still running: `kubectl get pods -n reliability-lab` → old Pods 1/1 Running, new Pod ErrImageNeverPull.
- **Show** rollout history: `kubectl rollout history deployment/app -n reliability-lab`.
- **Undo**: `kubectl rollout undo deployment/app -n reliability-lab`.
- **Verify**: `kubectl rollout status` → `successfully rolled out`.
- **Key message**: `maxUnavailable: 0` protected production. The rollout stalled but did not break anything.

### Minutes 29–30: Wrap-Up and Limitations (1 min)

- Explicitly state: "This lab runs on a single-node kind cluster. It is a learning tool, not a production reference."
- Point to `docs/limitations.md` for the full list of what is not covered.
- Questions.

---

*Last updated: 2026-10-11*
