# Setup Guide

This guide walks you through every step needed to get the lab running, from a fresh machine to
a deployed cluster. Read the section that matches your OS, then continue from
[Section 3: Clone the repository](#3-clone-the-repository) onward.

---

> **Resource requirements**
>
> | Resource | Minimum | Recommended |
> |---|---|---|
> | RAM | 6 GB available to WSL2 | 8 GB |
> | Disk | 5 GB free | 10 GB (images + kind node) |
> | CPU | 2 cores | 4 cores |
> | OS | Windows 11 22H2+ (WSL2) or Linux/macOS | — |
>
> kind runs a full Kubernetes control plane inside a Docker container. On a machine with less
> than 6 GB available to WSL2, the cluster may fail to start or become unresponsive under load.
> See [Section 9: WSL2 memory configuration](#9-wsl2-memory-configuration) before creating the cluster.

---

## 1. Windows 11 + WSL2 (Primary path)

All lab commands run inside WSL2 (Ubuntu). PowerShell is only used to invoke WSL2 or to set
WSL2 configuration. **Docker Desktop is not required** — Docker Engine runs directly inside the
WSL2 Ubuntu environment.

### 1.1 Enable WSL2 and install Ubuntu

Open PowerShell **as Administrator**:

```powershell
# PowerShell (Administrator)

# Enable WSL and install Ubuntu 22.04 in one step
wsl --install -d Ubuntu-22.04

# After the machine reboots, open the Ubuntu terminal and set your username/password.

# Confirm WSL version is 2
wsl --list --verbose
```

Expected output from `wsl --list --verbose`:

```
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
```

If VERSION shows `1`, upgrade with:

```powershell
wsl --set-version Ubuntu-22.04 2
```

### 1.2 Install Docker Engine, kind, and kubectl

The setup script installs all required tools inside WSL2. Run it once from PowerShell:

```powershell
# PowerShell
wsl -- bash scripts/wsl-setup.sh
```

Or, if you are already inside a WSL2 terminal:

```bash
# bash (WSL2 Ubuntu)
bash scripts/wsl-setup.sh
```

The script installs:

- **Docker Engine** (not Docker Desktop) via the official Docker apt repository
- **kind** v0.23.x via direct binary download from GitHub
- **kubectl** v1.30.x via the official Kubernetes apt repository
- **Python 3.13** via the deadsnakes PPA
- **pip**, **make**, **git**, **curl**, **jq** (via apt)

The script is idempotent — safe to re-run if interrupted.

### 1.3 Start Docker

Docker Engine inside WSL2 does not start automatically on boot (there is no systemd by default
on Ubuntu 22.04 WSL2). Start it manually each session:

```powershell
# PowerShell
wsl -- sudo service docker start
```

Or from a WSL2 terminal:

```bash
# bash (WSL2)
sudo service docker start
```

Confirm it is running:

```bash
# bash (WSL2)
docker info | grep "Server Version"
# Expected: Server Version: 24.x.x  (or later)
```

> **Tip — enable systemd (optional):** If you want Docker to start automatically, you can
> enable systemd in WSL2 by adding the following to `/etc/wsl.conf` inside WSL2 and then
> restarting WSL (`wsl --shutdown` from PowerShell):
>
> ```ini
> [boot]
> systemd=true
> ```
>
> After enabling systemd, use `sudo systemctl start docker` instead of `sudo service docker start`.

### 1.4 Verify all tools

```powershell
# PowerShell
wsl -- bash scripts/check-tools.sh
```

Expected output:

```
[OK] docker  24.x.x
[OK] kind    0.23.x
[OK] kubectl 1.30.x
[OK] python3 3.13.x
[OK] make    4.x
[OK] git     2.x
All tools present.
```

If any line shows `[FAIL]`, re-run `scripts/wsl-setup.sh` or install the missing tool manually.

### 1.5 PowerShell wrapper reference

Every `make` target in this lab can be run from PowerShell by prefixing with `wsl -- `:

| bash (WSL2) | PowerShell equivalent |
|---|---|
| `make cluster-create` | `wsl -- make cluster-create` |
| `make build` | `wsl -- make build` |
| `make load` | `wsl -- make load` |
| `make deploy` | `wsl -- make deploy` |
| `make port-forward` | `wsl -- make port-forward` |
| `make unit-test` | `wsl -- make unit-test` |
| `make validate-manifests` | `wsl -- make validate-manifests` |
| `make smoke-test` | `wsl -- make smoke-test` |
| `make clean` | `wsl -- make clean` |
| `make reset` | `wsl -- make reset` |
| `make help` | `wsl -- make help` |

All subsequent sections show bash commands. Prepend `wsl -- ` to run them from PowerShell.

---

## 2. Linux / macOS (Brief)

Install the required tools using your package manager or the official installation docs:

| Tool | Install reference |
|---|---|
| Docker Engine | https://docs.docker.com/engine/install/ |
| kind | `go install sigs.k8s.io/kind@v0.23.0` or https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |
| Python 3.13 | https://www.python.org/downloads/ or `pyenv install 3.13` |
| make | Pre-installed on macOS (Xcode CLT); `sudo apt install make` on Debian/Ubuntu |

After installing, verify:

```bash
bash scripts/check-tools.sh
```

All subsequent sections are identical for Linux and macOS — run the bash commands directly
without any `wsl -- ` prefix.

---

## 3. Clone the Repository

```bash
# bash (WSL2 or Linux/macOS)
git clone https://github.com/<your-org>/kubernetes-workload-reliability-lab.git
cd kubernetes-workload-reliability-lab
```

> If you are on Windows and cloned the repo outside WSL2 (e.g., on the Windows filesystem at
> `C:\Users\...`), access it from WSL2 at `/mnt/c/Users/...`. Performance will be slower than
> cloning directly inside the WSL2 home directory (`~/`). Cloning inside WSL2 is recommended.

---

## 4. Create the Cluster

```bash
# bash (WSL2)
make cluster-create
```

This runs:

```bash
kind create cluster \
  --name reliability-lab \
  --config kind-config.yaml
```

The `kind-config.yaml` configures a single-node cluster with the `reliability-lab` namespace
pre-configured. The first run downloads the kind node image (~200 MB).

Expected output:

```
Creating cluster "reliability-lab" ...
 ✓ Ensuring node image (kindest/node:v1.30.x) 🖼
 ✓ Preparing nodes 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-reliability-lab"
```

Verify the cluster is up:

```bash
kubectl cluster-info --context kind-reliability-lab
kubectl get nodes
```

Expected node output:

```
NAME                          STATUS   ROLES           AGE   VERSION
reliability-lab-control-plane Ready    control-plane   60s   v1.30.x
```

---

## 5. Build and Load the Image

The application image is built locally and loaded directly into the kind cluster node. There is
no registry push step.

```bash
# bash (WSL2)
make build    # builds reliability-app:1.0.0 from the Dockerfile
make load     # runs: kind load docker-image reliability-app:1.0.0 --name reliability-lab
```

Or in one step:

```bash
make build load
```

Expected output from `make build`:

```
[+] Building x.xs (y steps)
 ...
 => => naming to docker.io/library/reliability-app:1.0.0
```

Expected output from `make load`:

```
Image: "reliability-app:1.0.0" with ID "sha256:..." not yet present on node "reliability-lab-control-plane", loading...
```

Verify the image is present inside the kind node:

```bash
docker exec reliability-lab-control-plane crictl images | grep reliability-app
# Expected: reliability-app   1.0.0   sha256:...   <size>
```

---

## 6. Deploy

Apply all base manifests to the `reliability-lab` namespace:

```bash
# bash (WSL2)
make deploy
```

This runs `kubectl apply -f manifests/` which creates:

- The `reliability-lab` namespace
- A 2-replica Deployment (`reliability-app`)
- A ClusterIP Service on port 8080
- A PodDisruptionBudget (`minAvailable: 1`)
- A ConfigMap with app configuration

Expected output:

```
namespace/reliability-lab configured
deployment.apps/reliability-app created
service/reliability-app created
poddisruptionbudget.policy/reliability-app-pdb created
configmap/reliability-app-config created
```

---

## 7. Verify the Deployment

### 7.1 Check pod status

```bash
kubectl get pods -n reliability-lab
```

Expected output (after ~30 seconds for startup probe to pass):

```
NAME                               READY   STATUS    RESTARTS   AGE
reliability-app-6d8f9b7c4-abcd1   1/1     Running   0          45s
reliability-app-6d8f9b7c4-xyz99   1/1     Running   0          45s
```

If pods are in `Pending`, check node resources:

```bash
kubectl describe pod -n reliability-lab <pod-name>
# Look for: Events section — FailedScheduling or Insufficient memory
```

### 7.2 Forward the service port

```bash
# bash (WSL2) — runs in the foreground; keep this terminal open
make port-forward
# Equivalent: kubectl port-forward svc/reliability-app 8080:8080 -n reliability-lab
```

### 7.3 Hit the endpoints

Open a second terminal (bash or PowerShell):

```bash
# bash
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/startup
```

```powershell
# PowerShell
Invoke-RestMethod http://localhost:8080/
Invoke-RestMethod http://localhost:8080/health
```

Expected responses:

```json
# GET /
{"status": "ok", "app": "reliability-app"}

# GET /health
{"status": "healthy"}

# GET /ready
{"status": "ready"}

# GET /startup
{"status": "started"}
```

All four endpoints returning 200 means the deployment is working correctly.

---

## 8. Run Tests

Run tests in this order. Unit tests and manifest validation have no cluster dependency.

### 8.1 Unit tests

```bash
make unit-test
# Equivalent: pytest tests/ -v
```

Expected:

```
========================= 15 passed in x.xxs =========================
```

### 8.2 Manifest validation

```bash
make validate-manifests
# Equivalent: bash scripts/validate-manifests.sh
```

The script runs `kubectl apply --dry-run=client -f` over every YAML file. It expects:

```
[PASS] manifests/namespace.yaml
[PASS] manifests/deployment.yaml
[PASS] manifests/service.yaml
[PASS] manifests/pdb.yaml
[PASS] manifests/configmap.yaml
[PASS] scenarios/probe-failure/deployment.yaml
[PASS] scenarios/oom-kill/deployment.yaml
[PASS] scenarios/rolling-update/deployment.yaml
[PASS] scenarios/rolling-update/pdb.yaml
[PASS] scenarios/rolling-update/configmap.yaml
[WARN] scenarios/oom-kill/chaos-helper.yaml — no resource limits (expected, intentional)
10/10 passed, 1 warning
```

The warning on `chaos-helper.yaml` is intentional — that pod exists only to consume memory and
deliberately has no limits set.

### 8.3 Smoke tests (requires live cluster + port-forward)

With `make port-forward` running in another terminal:

```bash
make smoke-test
```

The smoke tests send HTTP requests to `http://localhost:8080` and assert:

- `GET /` → 200, body contains `"status": "ok"`
- `GET /health` → 200
- `GET /ready` → 200
- `GET /startup` → 200

If a smoke test fails, check that `make port-forward` is running and that all pods are in
`Running` state.

---

## 9. WSL2 Memory Configuration

By default, WSL2 may claim up to 50% of total system RAM (capped at 8 GB on most machines).
For this lab, at least **4 GB must be available inside WSL2** for kind to run stably.

Create or edit `C:\Users\<YourUsername>\.wslconfig` (on the Windows filesystem, not inside
WSL2):

```powershell
# PowerShell — open the file in Notepad
notepad $env:USERPROFILE\.wslconfig
```

Add or update these values:

```ini
[wsl2]
memory=6GB
processors=4
swap=2GB
```

Apply the new limits by restarting WSL2:

```powershell
# PowerShell
wsl --shutdown
# Wait a few seconds, then reopen your WSL2 terminal
wsl
```

Verify memory inside WSL2:

```bash
# bash (WSL2)
free -h
# The "total" row under "Mem" should show ~6.0G
```

> **Note:** Setting `memory` in `.wslconfig` caps the maximum RAM WSL2 can use. It does not
> pre-allocate that amount — WSL2 only uses what it needs. You can set this lower than 6 GB if
> your machine has limited RAM, but the cluster may become slow or fail to schedule pods under
> load.

---

## 10. Cleanup

### Remove deployed resources (keep the cluster)

```bash
make clean
# Equivalent: kubectl delete -f manifests/ --ignore-not-found
```

### Remove scenario resources

```bash
make scenario-clean
# Equivalent: kubectl delete -f scenarios/ -n reliability-lab --ignore-not-found
```

### Delete the kind cluster entirely

```bash
make reset
# Equivalent: kind delete cluster --name reliability-lab
```

This removes the cluster, the kind node container, and all Kubernetes state. The Docker image
`reliability-app:1.0.0` remains in your local Docker daemon. To remove it as well:

```bash
docker rmi reliability-app:1.0.0
```

### Full teardown

```bash
make reset
docker rmi reliability-app:1.0.0
```

After a full teardown, the next setup starts from [Section 4: Create the cluster](#4-create-the-cluster).

---

## Next Steps

| Document | What it covers |
|---|---|
| [`docs/scenarios.md`](scenarios.md) | Step-by-step walkthrough of each failure scenario |
| [`docs/architecture.md`](architecture.md) | Probe tuning rationale and design decisions |
| [`docs/troubleshooting.md`](troubleshooting.md) | Common errors and fixes |
