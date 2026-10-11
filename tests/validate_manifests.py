"""
validate_manifests.py — static YAML validation for all Kubernetes manifests
============================================================================
This script runs WITHOUT a live Kubernetes cluster, Docker daemon, or network
access.  It performs structural validation only — it cannot catch every
Kubernetes semantic error (e.g., a missing ServiceAccount referenced by a
Deployment) but it catches the most common authoring mistakes.

What is validated:
  1. Every YAML file in k8s/ is parseable (catches syntax errors)
  2. Every document has apiVersion, kind, metadata.name, and metadata.namespace
     (catches missing required fields that kubectl would reject)
  3. Specific resource-type checks (probe fields, image tag presence, etc.)
  4. Security context checks (warns about missing runAsNonRoot, etc.)
  5. No hardcoded real credentials patterns (basic secret-scanning heuristic)

What is NOT validated here:
  - Whether the image actually exists
  - Whether referenced ConfigMaps/Secrets/ServiceAccounts exist
  - RBAC authorisation
  - Actual probe behaviour
  These require a live cluster and are tested in tests/smoke/.

Run:
  python3 tests/validate_manifests.py
  # Or via Makefile:
  make validate-manifests
"""

import io
import re
import sys
from pathlib import Path

import yaml

# Force UTF-8 output so Unicode check-marks render on Windows terminals
# that default to cp1252.  Fall back silently if stdout is not wrappable.
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).parent.parent
K8S_DIR = REPO_ROOT / "k8s"

BOLD = "\033[1m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
RESET = "\033[0m"

# Resources that SHOULD have a namespace field
NAMESPACED_KINDS = {
    "Deployment", "Service", "ConfigMap", "Secret", "ServiceAccount",
    "ResourceQuota", "LimitRange", "Pod", "Job", "CronJob",
}

# Basic heuristic patterns for real-looking credentials
# These are intentionally simple — not a replacement for a proper secret scanner
CREDENTIAL_PATTERNS = [
    re.compile(r"(?i)password\s*[:=]\s*['\"]?[a-z0-9]{8,}", re.MULTILINE),
    re.compile(r"(?i)api[_-]?key\s*[:=]\s*['\"]?[a-z0-9]{16,}", re.MULTILINE),
    re.compile(r"(?i)token\s*[:=]\s*['\"]?[a-z0-9]{16,}", re.MULTILINE),
    re.compile(r"AKIA[0-9A-Z]{16}"),  # AWS access key pattern
    re.compile(r"ghp_[a-zA-Z0-9]{36}"),  # GitHub personal access token
]

PLACEHOLDER_VALUES = {"REPLACE_ME", "UkVQTEFDRV9NRQ==", "changeme", "placeholder"}


errors: list[str] = []
warnings: list[str] = []
passed: list[str] = []


def err(file: Path, msg: str) -> None:
    errors.append(f"{RED}✗ {file.relative_to(REPO_ROOT)}: {msg}{RESET}")


def warn(file: Path, msg: str) -> None:
    warnings.append(f"{YELLOW}⚠ {file.relative_to(REPO_ROOT)}: {msg}{RESET}")


def ok(file: Path, msg: str) -> None:
    passed.append(f"{GREEN}✓ {file.relative_to(REPO_ROOT)}: {msg}{RESET}")


def validate_file(path: Path) -> None:
    """Validate all YAML documents in a single file."""
    raw = path.read_text(encoding="utf-8")

    # ---- 1. Credential scan ------------------------------------------------
    for pattern in CREDENTIAL_PATTERNS:
        match = pattern.search(raw)
        if match:
            # Check if it's a known placeholder
            value = match.group(0)
            if not any(p in value for p in PLACEHOLDER_VALUES):
                err(path, f"Possible hardcoded credential: '{match.group(0)[:30]}...'")

    # ---- 2. YAML parse -----------------------------------------------------
    try:
        docs = list(yaml.safe_load_all(raw))
    except yaml.YAMLError as exc:
        err(path, f"YAML parse error: {exc}")
        return

    for i, doc in enumerate(docs):
        if doc is None:
            continue  # empty document separator

        suffix = f"[doc {i}]" if len(docs) > 1 else ""

        # ---- 3. Required top-level fields ----------------------------------
        for field in ("apiVersion", "kind"):
            if field not in doc:
                err(path, f"{suffix} missing required field '{field}'")
                return

        kind = doc.get("kind", "")
        meta = doc.get("metadata", {}) or {}
        name = meta.get("name", "")
        namespace = meta.get("namespace", "")

        if not name:
            err(path, f"{suffix} metadata.name is empty")

        if kind in NAMESPACED_KINDS and not namespace:
            err(path, f"{suffix} {kind}/{name} is missing metadata.namespace")

        # ---- 4. Deployment-specific checks ---------------------------------
        if kind == "Deployment":
            _check_deployment(path, doc, suffix)

        ok(path, f"{suffix} {kind}/{name} — structure valid")


def _check_deployment(path: Path, doc: dict, suffix: str) -> None:
    """Deployment-specific structural checks."""
    spec = doc.get("spec", {}) or {}
    template = spec.get("template", {}) or {}
    pod_spec = template.get("spec", {}) or {}
    containers = pod_spec.get("containers", []) or []

    for container in containers:
        cname = container.get("name", "<unnamed>")

        # Image must be present and not 'latest'
        image = container.get("image", "")
        if not image:
            err(path, f"{suffix} container '{cname}' has no image")
        elif image.endswith(":latest") or ":" not in image:
            warn(path, f"{suffix} container '{cname}' uses ':latest' or untagged image — not reproducible")

        # Resources must be set
        resources = container.get("resources", {}) or {}
        requests = resources.get("requests", {})
        limits = resources.get("limits", {})
        if not requests:
            warn(path, f"{suffix} container '{cname}' has no resource requests")
        if not limits:
            warn(path, f"{suffix} container '{cname}' has no resource limits")

        # At least one probe should be present
        has_probe = any(
            k in container
            for k in ("readinessProbe", "livenessProbe", "startupProbe")
        )
        if not has_probe:
            warn(path, f"{suffix} container '{cname}' has no probes configured")

        # Security context
        sc = container.get("securityContext", {}) or {}
        pod_sc = pod_spec.get("securityContext", {}) or {}

        if not sc.get("allowPrivilegeEscalation") is False:
            if sc.get("allowPrivilegeEscalation") is not False:
                warn(path, f"{suffix} container '{cname}': allowPrivilegeEscalation is not false")

        run_as_non_root = pod_sc.get("runAsNonRoot") or sc.get("runAsNonRoot")
        if not run_as_non_root:
            warn(path, f"{suffix} container '{cname}': runAsNonRoot not set")


def main() -> int:
    yaml_files = sorted(K8S_DIR.rglob("*.yaml"))

    if not yaml_files:
        print(f"{RED}No YAML files found in {K8S_DIR}{RESET}")
        return 1

    print(f"\n{BOLD}Validating {len(yaml_files)} manifest file(s) in k8s/{RESET}\n")

    for f in yaml_files:
        validate_file(f)

    # ---- Summary -----------------------------------------------------------
    for msg in passed:
        print(msg)

    if warnings:
        print()
        for msg in warnings:
            print(msg)

    if errors:
        print()
        for msg in errors:
            print(msg)

    print()
    print(f"{BOLD}Results: {GREEN}{len(passed)} passed{RESET}, "
          f"{YELLOW}{len(warnings)} warnings{RESET}, "
          f"{RED}{len(errors)} errors{RESET}")

    if errors:
        print(f"\n{RED}{BOLD}Validation FAILED.{RESET}")
        return 1

    if warnings:
        print(f"\n{YELLOW}Validation passed with warnings (review above).{RESET}")
    else:
        print(f"\n{GREEN}{BOLD}Validation passed.{RESET}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
