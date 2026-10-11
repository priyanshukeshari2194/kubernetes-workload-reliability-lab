# ===========================================================================
# Kubernetes Workload Reliability Lab — Makefile
# ===========================================================================
# All targets run locally via WSL2 + Docker Engine + kind.
# No cloud provider, paid API, or external cluster is required.
#
# PREREQUISITES (installed inside WSL2):
#   docker, kind, kubectl, python3 (>=3.11)
#
# Run `make help` to see available targets.
# Run `make check-tools` to verify prerequisites are installed.
#
# Windows PowerShell users: prefix targets with `wsl -- make <target>`
# from the repo root, or open a WSL2 terminal and run make directly.
# ===========================================================================

SHELL          := /bin/bash
.SHELLFLAGS    := -euo pipefail -c

# ---- Configuration ---------------------------------------------------------
IMAGE_NAME     ?= reliability-app
IMAGE_TAG      ?= 1.0.0
IMAGE          := $(IMAGE_NAME):$(IMAGE_TAG)
NAMESPACE      := reliability-lab
CLUSTER_NAME   := reliability-lab
KIND_CONFIG    := scripts/kind-config.yaml
PYTHON         := python3

# ---- Colours (safe fallback when NO_COLOR is set) --------------------------
ifneq ($(NO_COLOR),1)
  BOLD  := \033[1m
  GREEN := \033[32m
  YELLOW:= \033[33m
  RED   := \033[31m
  RESET := \033[0m
else
  BOLD  :=
  GREEN :=
  YELLOW:=
  RED   :=
  RESET :=
endif

.PHONY: help check-tools cluster-create cluster-delete \
        build load deploy deploy-all \
        port-forward smoke-test unit-test validate-manifests test-all \
        scenario-a scenario-a-reset \
        scenario-b scenario-b-reset \
        scenario-c scenario-c-reset \
        status logs events \
        clean reset \
        install-dev

# ---------------------------------------------------------------------------
# help — list all targets with descriptions
# ---------------------------------------------------------------------------
help:
	@printf '$(BOLD)Kubernetes Workload Reliability Lab$(RESET)\n'
	@printf '$(YELLOW)All operations are LOCAL — no cloud provider required.$(RESET)\n\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
check-tools: ## Verify all required tools are installed in WSL2
	@printf '$(BOLD)Checking prerequisites...$(RESET)\n'
	@bash scripts/check-tools.sh

install-dev: ## Install Python dev/test dependencies (run in WSL2 or any Python env)
	$(PYTHON) -m pip install -r app/requirements-dev.txt

# ---------------------------------------------------------------------------
# Cluster lifecycle (kind, local only)
# ---------------------------------------------------------------------------
cluster-create: ## Create a local kind cluster (kind-$(CLUSTER_NAME))
	@printf '$(BOLD)Creating kind cluster "$(CLUSTER_NAME)"...$(RESET)\n'
	@bash scripts/cluster-create.sh $(CLUSTER_NAME) $(KIND_CONFIG)

cluster-delete: ## Delete the local kind cluster
	@printf '$(BOLD)Deleting kind cluster "$(CLUSTER_NAME)"...$(RESET)\n'
	kind delete cluster --name $(CLUSTER_NAME)

# ---------------------------------------------------------------------------
# Image lifecycle
# ---------------------------------------------------------------------------
build: ## Build the application container image (requires Docker daemon)
	@printf '$(BOLD)Building $(IMAGE)...$(RESET)\n'
	docker build --tag $(IMAGE) --file app/Dockerfile app/
	@printf '$(GREEN)Build complete: $(IMAGE)$(RESET)\n'

load: ## Load the image into the kind cluster (no registry needed)
	@printf '$(BOLD)Loading $(IMAGE) into kind cluster "$(CLUSTER_NAME)"...$(RESET)\n'
	kind load docker-image $(IMAGE) --name $(CLUSTER_NAME)
	@printf '$(GREEN)Image loaded.$(RESET)\n'

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------
deploy: ## Apply the base Kubernetes manifests (namespace → configmap → ... → deployment)
	@printf '$(BOLD)Deploying base manifests to namespace $(NAMESPACE)...$(RESET)\n'
	kubectl apply -f k8s/base/namespace.yaml
	kubectl apply -f k8s/base/resourcequota.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/base/serviceaccount.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/base/configmap.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/base/secret.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/base/service.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/base/deployment.yaml -n $(NAMESPACE)
	@printf '$(BOLD)Waiting for rollout to complete...$(RESET)\n'
	kubectl rollout status deployment/reliability-app -n $(NAMESPACE) --timeout=120s
	@printf '$(GREEN)Deployment complete and ready.$(RESET)\n'

deploy-all: build load deploy ## Build image, load into kind, and deploy (full setup)

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------
port-forward: ## Forward localhost:8080 → Service port 80 (keep terminal open)
	@printf '$(BOLD)Forwarding localhost:8080 → $(NAMESPACE)/reliability-app-svc:80$(RESET)\n'
	@printf '$(YELLOW)Press Ctrl+C to stop.$(RESET)\n'
	kubectl port-forward svc/reliability-app-svc 8080:80 -n $(NAMESPACE)

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------
unit-test: ## Run unit tests (no cluster required)
	$(PYTHON) -m pytest tests/unit/ -v

validate-manifests: ## Validate YAML syntax and structure of all k8s manifests
	$(PYTHON) tests/validate_manifests.py

smoke-test: ## Run smoke tests against the deployed app (requires port-forward in another terminal)
	@printf '$(YELLOW)Ensure "make port-forward" is running in another terminal.$(RESET)\n'
	$(PYTHON) -m pytest tests/smoke/ -v

test-all: unit-test validate-manifests ## Run all non-cluster tests (CI-safe)

# ---------------------------------------------------------------------------
# Observability shortcuts
# ---------------------------------------------------------------------------
status: ## Show Pod, Service, and Endpoint status in the lab namespace
	@printf '$(BOLD)--- Pods ---$(RESET)\n'
	kubectl get pods -n $(NAMESPACE) -o wide
	@printf '\n$(BOLD)--- Services / Endpoints ---$(RESET)\n'
	kubectl get svc,endpoints -n $(NAMESPACE)
	@printf '\n$(BOLD)--- Deployment ---$(RESET)\n'
	kubectl get deployment -n $(NAMESPACE) -o wide

logs: ## Tail logs from the most recently scheduled reliability-app pod
	kubectl logs -l app.kubernetes.io/name=reliability-app -n $(NAMESPACE) \
	  --tail=50 --follow

events: ## Show recent Kubernetes events in the lab namespace
	kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp'

# ---------------------------------------------------------------------------
# Scenario A — Readiness probe failure
# ---------------------------------------------------------------------------
scenario-a: ## Trigger Scenario A: readiness probe failure
	@printf '$(BOLD)Scenario A: patching ConfigMap to set READY_TO_SERVE=false...$(RESET)\n'
	kubectl apply -f k8s/scenarios/a-readiness-failure/configmap-patch.yaml -n $(NAMESPACE)
	kubectl rollout restart deployment/reliability-app -n $(NAMESPACE)
	@printf '$(YELLOW)Watch with: kubectl get pods -n $(NAMESPACE) -w$(RESET)\n'
	@printf '$(YELLOW)After ~30s the readiness probe will fail. Check:$(RESET)\n'
	@printf '  kubectl describe pod -l app.kubernetes.io/name=reliability-app -n $(NAMESPACE)\n'
	@printf '  kubectl get endpoints reliability-app-svc -n $(NAMESPACE)\n'

scenario-a-reset: ## Reset Scenario A: restore working ConfigMap
	@printf '$(BOLD)Resetting Scenario A...$(RESET)\n'
	kubectl apply -f k8s/base/configmap.yaml -n $(NAMESPACE)
	kubectl rollout restart deployment/reliability-app -n $(NAMESPACE)
	kubectl rollout status deployment/reliability-app -n $(NAMESPACE) --timeout=120s
	@printf '$(GREEN)Scenario A reset. Application is ready.$(RESET)\n'

# ---------------------------------------------------------------------------
# Scenario B — Resource pressure (OOMKill)
# ---------------------------------------------------------------------------
scenario-b: ## Deploy Scenario B: memory-hog workload (OOMKill demo)
	@printf '$(BOLD)Scenario B: deploying memory-hog (will OOMKill within ~60s)...$(RESET)\n'
	kubectl apply -f k8s/scenarios/b-resource-pressure/memory-hog.yaml -n $(NAMESPACE)
	@printf '$(YELLOW)Watch with: kubectl get pods -n $(NAMESPACE) -w$(RESET)\n'
	@printf '$(YELLOW)After OOMKill look for exit code 137:$(RESET)\n'
	@printf '  kubectl describe pod -l lab.scenario=b-resource-pressure -n $(NAMESPACE)\n'

scenario-b-reset: ## Clean up Scenario B: remove memory-hog workload
	@printf '$(BOLD)Cleaning up Scenario B...$(RESET)\n'
	kubectl delete -f k8s/scenarios/b-resource-pressure/memory-hog.yaml \
	  -n $(NAMESPACE) --ignore-not-found
	@printf '$(GREEN)Scenario B cleaned up. Baseline app unaffected.$(RESET)\n'

# ---------------------------------------------------------------------------
# Scenario C — Bad rollout + recovery
# ---------------------------------------------------------------------------
scenario-c: ## Trigger Scenario C: deploy bad image tag (rollout failure)
	@printf '$(BOLD)Scenario C: applying bad deployment (image tag does-not-exist-999)...$(RESET)\n'
	kubectl apply -f k8s/scenarios/c-bad-rollout/bad-deployment.yaml -n $(NAMESPACE)
	@printf '$(YELLOW)Monitor rollout:$(RESET)\n'
	@printf '  kubectl rollout status deployment/reliability-app -n $(NAMESPACE)\n'
	@printf '  kubectl get pods -n $(NAMESPACE)\n'
	@printf '  kubectl rollout history deployment/reliability-app -n $(NAMESPACE)\n'

scenario-c-reset: ## Recover Scenario C: rollback to previous working revision
	@printf '$(BOLD)Recovering Scenario C: rolling back...$(RESET)\n'
	kubectl rollout undo deployment/reliability-app -n $(NAMESPACE)
	kubectl rollout status deployment/reliability-app -n $(NAMESPACE) --timeout=120s
	@printf '$(GREEN)Rollback complete. Application is serving traffic again.$(RESET)\n'

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
clean: ## Remove all lab resources from the cluster (keeps the cluster itself)
	@printf '$(BOLD)Removing namespace $(NAMESPACE) and all its resources...$(RESET)\n'
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
	@printf '$(GREEN)Namespace deleted. Cluster still running.$(RESET)\n'

reset: clean cluster-delete ## Full reset: delete namespace AND the kind cluster
	@printf '$(GREEN)Full reset complete. Run "make cluster-create deploy-all" to start fresh.$(RESET)\n'
