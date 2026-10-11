"""
Unit tests for the Reliability Lab application.

These tests run with `pytest` and do NOT require a running Kubernetes cluster,
a Docker daemon, or network access.  They use FastAPI's TestClient which runs
uvicorn synchronously inside the test process.

Run locally:
    cd app
    pip install -r requirements-dev.txt
    pytest ../tests/unit/ -v

Run in CI:
    Identical command; see .github/workflows/ci.yml.

What is tested here:
- Probe endpoints return the expected status codes
- The readiness endpoint respects READY_TO_SERVE
- The root endpoint returns version information

What is NOT tested here:
- Actual Kubernetes scheduling, probes, or Service routing
- Container image build
- Non-root execution (requires the built image)
- Resource limits
These are validated in tests/smoke/ against a live cluster.
"""

import os

import pytest
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# We import from the app directory.  When running from the repo root the
# pythonpath must include the app directory; pytest.ini handles this.
# ---------------------------------------------------------------------------
from main import app  # noqa: E402  (import after path setup)


@pytest.fixture()
def client() -> TestClient:
    """Return a FastAPI test client with default environment."""
    return TestClient(app, raise_server_exceptions=True)


# ---------------------------------------------------------------------------
# Startup probe
# ---------------------------------------------------------------------------

class TestStartupProbe:
    def test_returns_200(self, client: TestClient):
        response = client.get("/startup")
        assert response.status_code == 200

    def test_body_contains_status_started(self, client: TestClient):
        body = client.get("/startup").json()
        assert body["status"] == "started"

    def test_body_contains_uptime(self, client: TestClient):
        body = client.get("/startup").json()
        assert "uptime_seconds" in body
        assert body["uptime_seconds"] >= 0


# ---------------------------------------------------------------------------
# Liveness probe
# ---------------------------------------------------------------------------

class TestLivenessProbe:
    def test_returns_200(self, client: TestClient):
        response = client.get("/health")
        assert response.status_code == 200

    def test_body_contains_status_alive(self, client: TestClient):
        body = client.get("/health").json()
        assert body["status"] == "alive"

    def test_body_contains_version(self, client: TestClient):
        body = client.get("/health").json()
        assert "version" in body


# ---------------------------------------------------------------------------
# Readiness probe — the key endpoint for Scenario A
# ---------------------------------------------------------------------------

class TestReadinessProbe:
    def test_ready_when_env_is_true(self, client: TestClient, monkeypatch):
        monkeypatch.setenv("READY_TO_SERVE", "true")
        response = client.get("/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "ready"

    def test_not_ready_when_env_is_false(self, client: TestClient, monkeypatch):
        """
        This is the failure mode exploited in Scenario A.
        The probe returns 503; Kubernetes removes the Pod from Service
        endpoints but does NOT restart it (unlike a liveness failure).
        """
        monkeypatch.setenv("READY_TO_SERVE", "false")
        response = client.get("/ready")
        assert response.status_code == 503
        body = response.json()
        assert body["status"] == "not_ready"
        assert "READY_TO_SERVE" in body["reason"]

    def test_not_ready_when_env_is_missing(self, client: TestClient, monkeypatch):
        """
        The default value in _get_env is 'true', so absence of the variable
        means the app is ready.  This test documents that contract.
        """
        monkeypatch.delenv("READY_TO_SERVE", raising=False)
        response = client.get("/ready")
        assert response.status_code == 200

    def test_not_ready_when_env_is_arbitrary_string(self, client: TestClient, monkeypatch):
        """Any value other than 'true' (case-insensitive) should return 503."""
        monkeypatch.setenv("READY_TO_SERVE", "yes")
        response = client.get("/ready")
        assert response.status_code == 503

    def test_ready_when_env_is_TRUE_uppercase(self, client: TestClient, monkeypatch):
        """Case-insensitive comparison; 'TRUE' must be treated as ready."""
        monkeypatch.setenv("READY_TO_SERVE", "TRUE")
        response = client.get("/ready")
        assert response.status_code == 200


# ---------------------------------------------------------------------------
# Root endpoint
# ---------------------------------------------------------------------------

class TestRootEndpoint:
    def test_returns_200(self, client: TestClient):
        assert client.get("/").status_code == 200

    def test_body_contains_version(self, client: TestClient):
        body = client.get("/").json()
        assert "version" in body

    def test_body_contains_uptime(self, client: TestClient):
        body = client.get("/").json()
        assert "uptime_seconds" in body
        assert body["uptime_seconds"] >= 0

    def test_app_env_from_environment(self, client: TestClient, monkeypatch):
        monkeypatch.setenv("APP_ENV", "staging")
        response = client.get("/")
        assert response.json()["environment"] == "staging"
