# kubernetes-workload-reliability-lab

This repository is an educational lab that explores Kubernetes workload-reliability patterns —
pod disruption budgets, liveness/readiness/startup probes, rolling update strategies, and
simulated failure injection — using a minimal Python/FastAPI application running inside a
local `kind` cluster. It is **not** a production toolkit, a Helm chart library, or a
reference architecture for any cloud provider. Every component runs entirely inside WSL2 on a
local machine; there are no cloud provider dependencies of any kind.

> **This is an educational lab. It demonstrates patterns, not guarantees.**

---

## Table of Contents

1. [Status](#status)
2. [Quick Start](#quick-start)
3. [Failure Scenarios](#failure-scenarios)
4. [Prerequisites](#prerequisites)
5. [Project Structure](#project-structure)
6. [Testing](#testing)
7. [CI](#ci)
8. [Documentation](#documentation)
9. [Contributing](#contributing)
10. [License](#license)

---

## Status

| Area | State | Notes |
|---|---|---|
| Python unit tests | ✅ **TESTED** | 15/15 pass locally |
| Manifest validation | ✅ **TESTED** | 10/10 pass, 1 expected warning (no resource limits on chaos pod) |
| Docker image build | ✅ **TESTED** | `reliability-app:1.0.0` builds cleanly |
| GitHub Actions CI | ✅ **IMPLEMENTED** | Unit tests + YAML lint + Docker build; does **not** push to any registry |
| kind cluster creation | ⚠️ **UNTESTED** | Docker daemon was not running during development; script is written but unverified end-to-end |
| Live cluster deploy | ⚠️ **UNTESTED** | `make deploy` / `make port-forward` not run against a real cluster |
| Failure scenario injection | ⚠️ **UNTESTED** | Manifests exist; behaviour under a live cluster not observed |
| Smoke tests | ⚠️ **UNTESTED** | Require a running cluster; not executed during development |

### Production gaps (explicitly called out)

- Probes are tuned for a laptop lab, not production latency budgets.
- PodDisruptionBudget `minAvailable: 1` works only if you have ≥ 2 replicas; adjust before scaling down.
- No TLS anywhere — this is HTTP only.
- No RBAC configuration beyond the cluster default.
- Image is built locally and loaded via `kind load docker-image`; there is no registry push or image signing.
- Chaos injection is done by deploying a privileged pod — do **not** copy this pattern to a shared cluster.

---

## Quick Start

These commands assume you are on **Windows 11 with WSL2** (Ubuntu). All `make` targets run
inside WSL2. Prefix every `make` call with `wsl --` when running from PowerShell.

```powershell
# PowerShell — open a terminal and run these in order

# 1. Install tools inside WSL2 (one-time)
wsl -- bash scripts/wsl-setup.sh

# 2. Verify tool versions
wsl -- bash scripts/check-tools.sh

# 3. Start Docker inside WSL2 (each session)
wsl -- sudo service docker start

# 4. Clone (if you haven't already)
git clone https://github.com/<your-org>/kubernetes-workload-reliability-lab.git
cd kubernetes-workload-reliability-lab

# 5. Create the kind cluster
wsl -- make cluster-create

# 6. Build the container image and load it into kind
wsl -- make build load

# 7. Deploy all manifests to the reliability-lab namespace
wsl -- make deploy

# 8. Verify pods are running
wsl -- kubectl get pods -n reliability-lab

# 9. Forward the service port and hit the health endpoint
wsl -- make port-forward
# In a second terminal:
curl http://localhost:8080/health
```

Expected pod output (after `make deploy`):

```
NAME                          READY   STATUS    RESTARTS   AGE
reliability-app-<hash>        1/1     Running   0          30s
reliability-app-<hash>        1/1     Running   0          28s
```

If any pod stays in `Pending` or `CrashLoopBackOff`, see [`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## Failure Scenarios

Three scenarios are included, each in its own manifest directory under `scenarios/`:

| Scenario | One-liner |
|---|---|
| **probe-failure** | Liveness probe is pointed at a non-existent path; Kubernetes restarts the container after the failure threshold is crossed. |
| **oom-kill** | A sidecar process allocates memory beyond the container limit, triggering an OOM kill and demonstrating restart behaviour. |
| **rolling-update** | A `RollingUpdate` deployment strategy combined with a PodDisruptionBudget keeps at least one replica available while new pods come up. |

Run a scenario:

```bash
# bash (inside WSL2)
make scenario-probe-failure   # deploys the probe-failure scenario
make scenario-oom              # deploys the OOM scenario
make scenario-rolling          # triggers a rolling update
make scenario-clean            # removes scenario resources
```

---

## Prerequisites

| Tool | Minimum version | Install command |
|---|---|---|
| WSL2 (Ubuntu 22.04) | WSL version 2 | `wsl --install -d Ubuntu-22.04` (PowerShell, admin) |
| Docker Engine | 24.x | `scripts/wsl-setup.sh` installs this |
| kind | 0.23.x | `scripts/wsl-setup.sh` installs this |
| kubectl | 1.30.x | `scripts/wsl-setup.sh` installs this |
| Python | 3.13 | `scripts/wsl-setup.sh` installs via deadsnakes PPA |
| make | 4.x (GNU) | Pre-installed on Ubuntu; `sudo apt install make` if missing |
| git | any modern | Pre-installed on Ubuntu |

> **Docker Desktop is not required.** This lab uses Docker Engine installed directly inside
> WSL2. Docker Desktop is optional and not tested with this setup.

All tool checks can be run at any time:

```bash
bash scripts/check-tools.sh
```

---

## Project Structure

```
kubernetes-workload-reliability-lab/
│
├── app/                          # FastAPI application
│   ├── main.py                   # Single-file app; endpoints: /, /health, /ready, /startup
│   ├── requirements.txt          # Runtime deps: fastapi, uvicorn
│   └── requirements-dev.txt      # Dev/test deps: pytest, httpx, ruff
│
├── tests/                        # pytest suite (15 unit tests)
│   ├── test_main.py              # Tests for all four endpoints + probe edge cases
│   └── conftest.py               # Shared fixtures (TestClient)
│
├── manifests/                    # Base Kubernetes manifests
│   ├── namespace.yaml            # reliability-lab namespace
│   ├── deployment.yaml           # 2-replica Deployment, probes configured
│   ├── service.yaml              # ClusterIP Service on port 8080
│   ├── pdb.yaml                  # PodDisruptionBudget minAvailable: 1
│   └── configmap.yaml            # App configuration (log level, app name)
│
├── scenarios/                    # Failure injection overlays
│   ├── probe-failure/            # Broken liveness probe manifest
│   ├── oom-kill/                 # Memory-hungry sidecar manifest
│   └── rolling-update/           # Rolling update + PDB demonstration
│
├── scripts/                      # Setup and helper scripts
│   ├── wsl-setup.sh              # Installs Docker Engine, kind, kubectl, Python 3.13
│   ├── check-tools.sh            # Validates tool versions; exits non-zero on failure
│   ├── validate-manifests.sh     # kubectl --dry-run=client over all YAML files
│   └── port-forward.sh           # kubectl port-forward wrapper
│
├── .github/
│   └── workflows/
│       └── ci.yml                # GitHub Actions: unit tests, YAML lint, Docker build
│
├── Dockerfile                    # Multi-stage build; final image: reliability-app:1.0.0
├── Makefile                      # All dev tasks as make targets (see `make help`)
├── pyproject.toml                # Ruff + pytest configuration
├── docs/
│   ├── setup.md                  # Full environment setup guide (start here after README)
│   ├── architecture.md           # Design decisions and probe tuning rationale
│   ├── scenarios.md              # Detailed walkthrough of each failure scenario
│   └── troubleshooting.md        # Common errors and fixes
└── README.md                     # This file
```

---

## Testing

Three test categories exist. Run them in order — unit tests have no dependencies, smoke and
cluster tests require a running kind cluster.

### Unit tests

Test the FastAPI app directly via `httpx.AsyncClient`. No Kubernetes, no Docker.

```bash
# bash
make unit-test
# or directly:
pytest tests/ -v
```

Expected output: `15 passed in <Xs>`.

### Manifest validation (static)

Runs `kubectl apply --dry-run=client` against every YAML file. Does **not** require a running
cluster. One expected warning about missing resource limits on the chaos helper pod is suppressed
in CI but shown locally.

```bash
make validate-manifests
# Expected: 10/10 passed, 1 warning (chaos pod — intentional)
```

### Smoke tests (require live cluster)

Exercise the deployed service over `port-forward`. Require `make deploy` to have succeeded.

```bash
make smoke-test
```

What the smoke tests check:

- `GET /` returns HTTP 200 with `{"status": "ok"}`.
- `GET /health` returns HTTP 200.
- `GET /ready` returns HTTP 200 when the app is ready, 503 during simulated not-ready state.
- `GET /startup` returns HTTP 200 after startup delay elapses.

### Cluster tests (require live cluster)

Validate Kubernetes behaviour — probe restarts, PDB enforcement, rolling update sequencing.
These are documented in [`docs/scenarios.md`](docs/scenarios.md) as manual step-by-step
walkthroughs rather than automated scripts, because timing and pod scheduling are
non-deterministic on a laptop.

---

## CI

GitHub Actions runs on every push and pull request to `main`.

Pipeline steps (`.github/workflows/ci.yml`):

1. **Unit tests** — `pytest tests/ -v` on Python 3.13.
2. **YAML lint** — `yamllint` over all `manifests/` and `scenarios/` files.
3. **Docker build** — builds `reliability-app:1.0.0`; image is **not** pushed anywhere.

The pipeline does **not**:

- Start a kind cluster.
- Run smoke or cluster tests.
- Push to Docker Hub, GHCR, or any other registry.
- Deploy to any cloud environment.

---

## Documentation

| File | Contents |
|---|---|
| [`docs/setup.md`](docs/setup.md) | Full setup guide for Windows/WSL2, Linux, and macOS |
| [`docs/architecture.md`](docs/architecture.md) | Design decisions, probe configuration rationale |
| [`docs/scenarios.md`](docs/scenarios.md) | Step-by-step walkthrough of each failure scenario |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Common errors and fixes |

Start with [`docs/setup.md`](docs/setup.md) if this is your first time.

---

## Contributing

Contributions are welcome. Please follow these guidelines:

1. **Keep it local.** No cloud provider dependencies. All scenarios must run on `kind` inside WSL2.
2. **Keep tests passing.** Run `make unit-test` and `make validate-manifests` before opening a PR.
3. **Honest documentation.** If something is untested, say so. Do not describe aspirational
   behaviour as current behaviour.
4. **No marketing language.** Terms like "enterprise-grade", "production-ready", or
   "zero-downtime" are not accurate for a laptop lab and should not appear in docs or comments.
5. **Small PRs.** One scenario or one fix per pull request.

Opening an issue before a large change is appreciated.

### Running the full local check

```bash
make lint          # ruff check
make unit-test     # pytest
make validate-manifests
```

All three must pass before a PR is considered ready.

---

## License

MIT License. See [`LICENSE`](LICENSE) for the full text.

This project has no affiliation with the Kubernetes project, the Cloud Native Computing
Foundation, or any cloud provider.
