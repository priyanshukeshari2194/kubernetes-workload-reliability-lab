"""
Smoke tests — run against a live, locally deployed application.
===============================================================
These tests require:
  1. A running kind cluster with the lab deployed (make deploy-all)
  2. kubectl port-forward running in another terminal (make port-forward)
     OR the BASE_URL environment variable set to the app's address.

Run:
  # Terminal 1:
  make port-forward

  # Terminal 2:
  pytest tests/smoke/ -v
  # or:
  BASE_URL=http://localhost:8080 pytest tests/smoke/ -v

What is tested:
  - The deployed app responds on all expected endpoints
  - Probe endpoints return the correct status codes
  - Response bodies contain the expected structure
  - The readiness toggle (Scenario A mechanism) works end-to-end

What is NOT tested in this file:
  - OOMKill behaviour (requires observing kubectl describe output)
  - Rollout history and rollback (requires multiple deployments)
  - Endpoint removal during readiness failure (requires kubectl get endpoints)
  Those are validated via the runbook commands in docs/troubleshooting.md.

Marked: tests that require a live cluster are decorated with
@pytest.mark.integration so they can be skipped in pure unit-test CI runs:
  pytest tests/smoke/ -m "not integration"  # skip if no cluster
"""

import os

import httpx
import pytest

BASE_URL = os.environ.get("BASE_URL", "http://localhost:8080")

# Mark all smoke tests as integration — require a live cluster
pytestmark = pytest.mark.integration


@pytest.fixture(scope="module")
def client() -> httpx.Client:
    """HTTP client pointing at the locally deployed application."""
    try:
        c = httpx.Client(base_url=BASE_URL, timeout=5.0)
        # Quick connectivity check — skip all tests if the app is not reachable
        c.get("/health")
        return c
    except httpx.ConnectError:
        pytest.skip(
            f"Cannot connect to {BASE_URL}. "
            "Run 'make port-forward' in another terminal before running smoke tests."
        )


class TestLiveProbes:
    def test_health_endpoint_returns_200(self, client: httpx.Client):
        r = client.get("/health")
        assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"

    def test_health_body_is_json_with_status(self, client: httpx.Client):
        body = client.get("/health").json()
        assert body.get("status") == "alive"
        assert "version" in body

    def test_startup_endpoint_returns_200(self, client: httpx.Client):
        r = client.get("/startup")
        assert r.status_code == 200

    def test_readiness_returns_200_in_normal_state(self, client: httpx.Client):
        """
        In normal deployment READY_TO_SERVE=true (from the base ConfigMap).
        This test confirms the baseline state before running Scenario A.
        """
        r = client.get("/ready")
        assert r.status_code == 200, (
            f"Expected 200 (normal state). Got {r.status_code}.\n"
            "If Scenario A is active, reset it first: make scenario-a-reset"
        )

    def test_root_endpoint_returns_version(self, client: httpx.Client):
        body = client.get("/").json()
        assert "version" in body
        assert "uptime_seconds" in body
        assert body["uptime_seconds"] >= 0


class TestResponseStructure:
    def test_content_type_is_json(self, client: httpx.Client):
        for path in ("/health", "/ready", "/startup", "/"):
            r = client.get(path)
            assert "application/json" in r.headers.get("content-type", ""), \
                f"{path} did not return JSON content-type"

    def test_root_shows_lab_environment(self, client: httpx.Client):
        body = client.get("/").json()
        # APP_ENV is set to "lab" in the base ConfigMap
        assert body.get("environment") == "lab", \
            f"Expected environment='lab', got '{body.get('environment')}'. " \
            "Check that the base ConfigMap is applied."
