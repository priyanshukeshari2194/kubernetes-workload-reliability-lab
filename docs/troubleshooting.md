# Troubleshooting Guide: kubernetes-workload-reliability-lab

> **Output notation used in this document:**
> - ✅ **Actual observed output** — captured from a running cluster during authoring.
> - 📋 **Representative example** — the format and field values shown are accurate for the described scenario, but were not captured from a live cluster during authoring because the Docker daemon was not running in the authoring environment. Field values (Pod names, IPs, timestamps) will differ in your environment.

---

## Section 1: Common WSL2 / Docker Problems

### 1.1 Docker daemon not running

**Symptom:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock.
Is the docker daemon running?
```
or, in PowerShell:
```
error during connect: ... pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

**Cause:** Docker Desktop is not started, or its WSL2 backend has not initialised.

**Fix:**
1. Open Docker Desktop from the Start menu and wait for the whale icon in the system tray to stop animating.
2. In a WSL2 terminal, verify the socket is available:
   ```bash
   docker info
   ```
   Expected: long output ending in `Server Version: ...`
3. If Docker Desktop is running but WSL2 still cannot reach the daemon, restart the WSL2 distribution:
   ```powershell
   wsl --shutdown
   ```
   Then reopen the WSL2 terminal.

---

### 1.2 Permission denied on Docker socket

**Symptom:**
```
permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock
```

**Cause:** Your Linux user inside WSL2 is not a member of the `docker` group.

**Fix:**
```bash
sudo usermod -aG docker $USER
newgrp docker
```
If the problem persists after `newgrp docker`, log out of the WSL2 session and back in.

---

### 1.3 `kind` cannot create a cluster

**Symptom:**
```
ERROR: failed to create cluster: failed to init node with docker: ...
```
or:
```
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "reliability-lab"
```

**Fix (cluster already exists):**
```bash
kind delete cluster --name reliability-lab
kind create cluster --name reliability-lab --config kind-config.yaml
```

**Fix (Docker networking issue):**
```bash
docker system prune -f
kind create cluster --name reliability-lab --config kind-config.yaml
```

**Fix (port conflict — 80/443 already in use):**
Edit `kind-config.yaml` and change `hostPort` values to unused ports (e.g., 8080/8443).

---

### 1.4 Image not loaded into kind

**Symptom (during scenario C):**
```
ErrImageNeverPull
```
or:
```
Failed to pull image "app:v2": rpc error: code = Unknown desc = failed to pull and unpack image: ... not found
```

**Cause:** You built the Docker image on your host but did not load it into the kind cluster's containerd runtime.

**Fix:**
```bash
docker build -t app:v1 .
kind load docker-image app:v1 --name reliability-lab
```
Verify the image is available inside kind:
```bash
docker exec -it reliability-lab-control-plane crictl images | grep app
```
📋 Representative expected output:
```
docker.io/library/app    v1    sha256:abc123...   12.3MB
```

---

## Section 2: Common `kubectl` Problems

### 2.1 Context not set / wrong cluster

**Symptom:**
```
The connection to the server localhost:8080 was refused
```
or commands target the wrong cluster.

**Fix:**
```bash
kubectl config get-contexts
kubectl config use-context kind-reliability-lab
kubectl config current-context
```
📋 Representative expected output:
```
kind-reliability-lab
```

---

### 2.2 Wrong namespace

**Symptom:** `kubectl get pods` returns `No resources found in default namespace.`

**Fix:** Always specify the namespace or set it as default:
```bash
# Specify per command
kubectl get pods -n reliability-lab

# Set as default for the current context
kubectl config set-context --current --namespace=reliability-lab
```

---

### 2.3 `kubectl top pods` not working

**Symptom:**
```
error: Metrics API not available
```

**Cause:** `metrics-server` is not installed (it is not part of the base kind cluster).

**Fix (optional):** Install the metrics-server with toleration for the kind node:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```
Wait 60 seconds for metrics to populate. `kubectl top pods -n reliability-lab` will then work.

---

## Section 3: Scenario A Runbook — Readiness Probe Failure

**Goal:** Demonstrate that a Pod failing its readiness probe is removed from Service routing without being restarted.

### Step 1 — Trigger the failure

```bash
kubectl exec -n reliability-lab deploy/app -- \
  sh -c 'kill -STOP 1'
```
This sends SIGSTOP to PID 1, pausing the process so the HTTP server stops responding to the readiness probe.

Alternatively (if the app exposes a toggle endpoint):
```bash
kubectl exec -n reliability-lab deploy/app -- \
  sh -c 'touch /tmp/unhealthy'
```

### Step 2 — Observe Pod becoming NotReady

```bash
kubectl get pods -n reliability-lab -w
```
📋 Representative expected output (after ~10–30 seconds, depending on `failureThreshold × periodSeconds`):
```
NAME                   READY   STATUS    RESTARTS   AGE
app-7d4f9b6c8-xk2pq   1/1     Running   0          4m12s
app-7d4f9b6c8-xk2pq   0/1     Running   0          4m42s
```
Note: `READY 0/1` — the Pod is still `Running` (not restarted), just not ready.

### Step 3 — Describe the Pod to see the probe failure

```bash
kubectl describe pod -n reliability-lab -l app=app
```
📋 Representative expected output (in the `Events` section):
```
Events:
  Type     Reason     Age   From               Message
  ----     ------     ----  ----               -------
  Warning  Unhealthy  30s   kubelet            Readiness probe failed: HTTP probe failed with statuscode: 503
  Warning  Unhealthy  20s   kubelet            Readiness probe failed: HTTP probe failed with statuscode: 503
  Warning  Unhealthy  10s   kubelet            Readiness probe failed: HTTP probe failed with statuscode: 503
```
Also look at the `Conditions` section:
```
Conditions:
  Type              Status
  Initialized       True
  Ready             False      ← Pod is NOT ready
  ContainersReady   False
  PodScheduled      True
```

### Step 4 — Verify the Endpoints object has no ready addresses

```bash
kubectl get endpoints -n reliability-lab app
```
📋 Representative expected output:
```
NAME   ENDPOINTS   AGE
app    <none>      5m10s
```
The `<none>` confirms the Pod IP has been removed from the `addresses[]` list. Traffic to the Service VIP will now return "connection refused" or time out.

For verbose detail:
```bash
kubectl describe endpoints -n reliability-lab app
```
📋 Representative expected output:
```
Name:         app
Namespace:    reliability-lab
Labels:       ...
Subsets:
  NotReadyAddresses:  10.244.0.5     ← Pod IP is here, not in Addresses
  Ports:
    Name     Port  Protocol
    ----     ----  --------
    http     8080  TCP
```

### Step 5 — Verify recovery

Resume the process (undo SIGSTOP):
```bash
kubectl exec -n reliability-lab deploy/app -- \
  sh -c 'kill -CONT 1'
```
Wait for `successThreshold` readiness probes to pass (default: 1 success), then:
```bash
kubectl get endpoints -n reliability-lab app
```
📋 Representative expected output after recovery:
```
NAME   ENDPOINTS         AGE
app    10.244.0.5:8080   6m30s
```
The Pod IP is back in `addresses[]`. Service routing is restored.

---

## Section 4: Scenario B Runbook — OOMKilled / CrashLoopBackOff

**Goal:** Demonstrate that exceeding `resources.limits.memory` causes OOMKill (exit 137) and subsequent CrashLoopBackOff.

### Step 1 — Trigger memory exhaustion

```bash
# If the app has a stress endpoint:
kubectl exec -n reliability-lab deploy/app -- \
  sh -c 'cat /dev/zero | head -c 200m > /dev/null'
```
Or apply a manifest that sets an unrealistically low memory limit:
```bash
kubectl set resources deployment/app -n reliability-lab \
  --limits=memory=10Mi
```

### Step 2 — Watch the Pod cycling

```bash
kubectl get pods -n reliability-lab -w
```
📋 Representative expected output:
```
NAME                   READY   STATUS             RESTARTS   AGE
app-7d4f9b6c8-xk2pq   1/1     Running            0          1m
app-7d4f9b6c8-xk2pq   0/1     OOMKilled          0          1m15s
app-7d4f9b6c8-xk2pq   0/1     CrashLoopBackOff   1          1m25s
app-7d4f9b6c8-xk2pq   1/1     Running            2          2m10s
app-7d4f9b6c8-xk2pq   0/1     OOMKilled          2          2m20s
app-7d4f9b6c8-xk2pq   0/1     CrashLoopBackOff   3          2m30s
```

### Step 3 — Describe the Pod to see OOMKilled reason

```bash
kubectl describe pod -n reliability-lab -l app=app
```
📋 Representative expected output (in the `Containers` section):
```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Sun, 11 Oct 2026 20:01:00 +0530
      Finished:     Sun, 11 Oct 2026 20:01:15 +0530
    Ready:          False
    Restart Count:  3
```
Exit code **137** = 128 + 9 (SIGKILL). The kernel OOM killer sends SIGKILL when a container's cgroup memory limit is exceeded.

### Step 4 — Check resource usage (requires metrics-server)

```bash
kubectl top pods -n reliability-lab
```
📋 Representative expected output (if metrics-server is installed):
```
NAME                   CPU(cores)   MEMORY(bytes)
app-7d4f9b6c8-xk2pq   2m           9Mi
```
> **Note:** `kubectl top pods` requires `metrics-server` to be deployed in the cluster. It is **not** available in a default kind cluster. If you see `error: Metrics API not available`, see Section 2.3. The OOMKilled behaviour itself does not require metrics-server — it is enforced by the kernel cgroup controller regardless.

---

## Section 5: Scenario C Runbook — Bad Image / Stuck Rollout

**Goal:** Demonstrate that a rolling update with a bad image (`imagePullPolicy: Never` + missing image) stalls without taking down the existing Pods.

### Step 1 — Apply a bad image update

```bash
kubectl set image deployment/app -n reliability-lab \
  app=app:v-does-not-exist \
  --record
```
> **Note:** `--record` is deprecated in newer Kubernetes versions. Use the `kubernetes.io/change-cause` annotation manually instead:
> ```bash
> kubectl annotate deployment/app -n reliability-lab \
>   kubernetes.io/change-cause="test bad image rollout"
> ```

### Step 2 — Watch the rollout stall

```bash
kubectl rollout status deployment/app -n reliability-lab
```
📋 Representative expected output:
```
Waiting for deployment "app" rollout to finish: 1 out of 3 new replicas have been updated...
```
This command will **hang** — it will not return. Press `Ctrl+C` and investigate.

### Step 3 — Observe ErrImageNeverPull

```bash
kubectl get pods -n reliability-lab
```
📋 Representative expected output:
```
NAME                    READY   STATUS              RESTARTS   AGE
app-7d4f9b6c8-xk2pq    1/1     Running             0          10m     ← old Pod, still healthy
app-7d4f9b6c8-mp9rs    1/1     Running             0          10m     ← old Pod, still healthy
app-7d4f9b6c8-qt1lv    1/1     Running             0          10m     ← old Pod, still healthy
app-5b8f2d9c7-zzz99    0/1     ErrImageNeverPull   0          30s     ← new Pod, stuck
```
The old Pods are untouched because `maxUnavailable: 0` — the Deployment will not kill old Pods until a new one is Ready.

### Step 4 — View rollout history

```bash
kubectl rollout history deployment/app -n reliability-lab
```
📋 Representative expected output:
```
deployment.apps/app
REVISION  CHANGE-CAUSE
1         <none>
2         test bad image rollout
```

### Step 5 — Roll back

```bash
kubectl rollout undo deployment/app -n reliability-lab
```
📋 Representative expected output:
```
deployment.apps/app rolled back
```

### Step 6 — Verify recovery

```bash
kubectl rollout status deployment/app -n reliability-lab
```
📋 Representative expected output:
```
deployment "app" successfully rolled out
```

```bash
kubectl get pods -n reliability-lab
```
📋 Representative expected output:
```
NAME                   READY   STATUS    RESTARTS   AGE
app-7d4f9b6c8-xk2pq   1/1     Running   0          12m
app-7d4f9b6c8-mp9rs   1/1     Running   0          12m
app-7d4f9b6c8-qt1lv   1/1     Running   0          12m
```
All Pods running, no bad image in sight. The bad ReplicaSet has been scaled to 0.

---

## Section 6: Port-Forward Troubleshooting

### 6.1 Port-forward command

```bash
kubectl port-forward svc/app 8080:80 -n reliability-lab
```
Expected output:
```
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

### 6.2 Port already in use

**Symptom:**
```
error: unable to listen on any of the requested ports: [{8080 8080}]
```

**Fix:** Find and kill the process using port 8080:
```powershell
# PowerShell (Windows host)
netstat -ano | findstr :8080
taskkill /PID <PID> /F
```
```bash
# Linux / WSL2
lsof -i :8080
kill -9 <PID>
```
Or use a different local port:
```bash
kubectl port-forward svc/app 9090:80 -n reliability-lab
```

### 6.3 Port-forward drops after a few minutes

**Cause:** `kubectl port-forward` is not designed for sustained production traffic. It is a development/debug tool that runs over the API server websocket and will drop with inactivity or network hiccups.

**Fix for sustained testing:** Use a loop to re-establish:
```bash
while true; do
  kubectl port-forward svc/app 8080:80 -n reliability-lab
  sleep 1
done
```

### 6.4 Port-forward works but the app returns errors

Check Pod logs:
```bash
kubectl logs -n reliability-lab -l app=app --tail=50
```
Check if the Pod is actually ready:
```bash
kubectl get pods -n reliability-lab
```
If `READY` is `0/1`, the Pod is not serving traffic — but `port-forward` bypasses the Service and Endpoints, so it **will** forward even to a NotReady Pod. This can be confusing during Scenario A. Use the Service (via `port-forward svc/`) not the Pod directly to see the full routing behaviour.

---

*Last updated: 2026-10-11*
