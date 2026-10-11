# PowerShell helper commands for Windows users
# ============================================
# Run these from PowerShell on Windows.
# They call into WSL2 where Docker, kind, and kubectl are installed.
#
# Prerequisites:
#   1. WSL2 installed with Ubuntu distro
#   2. Docker Engine running inside WSL2: wsl -- sudo service docker start
#   3. kind and kubectl installed inside WSL2 (run scripts/wsl-setup.sh)
#   4. Lab deployed: wsl -- make deploy-all
#
# IMPORTANT: All Kubernetes operations happen inside WSL2.
# kubectl.exe on Windows PATH (from Docker Desktop) also works for
# cluster inspection, but image builds must use wsl docker.

# ------------------------------------------------------------------
# Environment setup
# ------------------------------------------------------------------

# Start Docker Engine inside WSL2 (run once per WSL2 session)
wsl -- sudo service docker start

# Verify prerequisites
wsl -- bash scripts/check-tools.sh

# ------------------------------------------------------------------
# Cluster management
# ------------------------------------------------------------------

# Create the kind cluster
wsl -- make cluster-create

# Delete the cluster
wsl -- make cluster-delete

# ------------------------------------------------------------------
# Build and deploy
# ------------------------------------------------------------------

# Build image, load into kind, deploy all manifests
wsl -- make deploy-all

# Or step by step:
wsl -- make build
wsl -- make load
wsl -- make deploy

# ------------------------------------------------------------------
# Access
# ------------------------------------------------------------------

# Forward localhost:8080 to the Service (keep this terminal open)
wsl -- make port-forward

# In a NEW PowerShell window, test the app:
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8080/ready
Invoke-RestMethod http://localhost:8080/

# ------------------------------------------------------------------
# Testing (no cluster required)
# ------------------------------------------------------------------

# Run unit tests
wsl -- make unit-test

# Validate manifests
wsl -- make validate-manifests

# Run smoke tests (requires port-forward running)
wsl -- make smoke-test

# ------------------------------------------------------------------
# Observability
# ------------------------------------------------------------------

# Check pod status
wsl -- make status

# Tail application logs
wsl -- make logs

# Show recent events
wsl -- make events

# Direct kubectl commands (works from PowerShell if kubectl on PATH):
kubectl get pods -n reliability-lab
kubectl describe pod -l app.kubernetes.io/name=reliability-app -n reliability-lab
kubectl get endpoints reliability-app-svc -n reliability-lab
kubectl top pods -n reliability-lab  # requires metrics-server

# ------------------------------------------------------------------
# Scenario A — Readiness probe failure
# ------------------------------------------------------------------
wsl -- make scenario-a
# (wait 30s, then observe)
kubectl get pods -n reliability-lab
kubectl get endpoints reliability-app-svc -n reliability-lab
# Reset:
wsl -- make scenario-a-reset

# ------------------------------------------------------------------
# Scenario B — Resource pressure (OOMKill)
# ------------------------------------------------------------------
wsl -- make scenario-b
# (watch in real time)
kubectl get pods -n reliability-lab -w
kubectl describe pod -l lab.scenario=b-resource-pressure -n reliability-lab
# Reset:
wsl -- make scenario-b-reset

# ------------------------------------------------------------------
# Scenario C — Bad rollout and rollback
# ------------------------------------------------------------------
wsl -- make scenario-c
kubectl rollout status deployment/reliability-app -n reliability-lab
kubectl rollout history deployment/reliability-app -n reliability-lab
kubectl get pods -n reliability-lab
# Rollback:
wsl -- make scenario-c-reset

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------

# Remove all lab resources (keeps cluster)
wsl -- make clean

# Full reset: remove resources AND cluster
wsl -- make reset
