"""
Kubernetes Workload Reliability Lab — Sample Application
=========================================================
A minimal FastAPI service that exposes the three probe endpoints Kubernetes
uses to manage container lifecycle, plus a controllable failure mode that
powers Scenario A (readiness-probe failure).

Design decisions
----------------
* We use FastAPI because it is lightweight, self-documenting, and easy to read
  in a conference presentation.  The dependency set is intentionally small.
* The /ready endpoint checks an environment variable (READY_TO_SERVE).
  Setting it to "false" causes readiness to fail without crashing the process,
  which is the exact behaviour Kubernetes uses to keep a Pod out of Service
  rotation without restarting it.
* The /health endpoint always returns 200 as long as the process is alive.
  Kubernetes uses this for liveness; if it fails, the container is restarted.
* The /startup endpoint returns 200 immediately; in the manifest we give it a
  longer failureThreshold so slow-starting containers are not killed early.
* We intentionally do NOT use any database or external service so the lab
  works fully offline and in CI.
"""

import logging
import os
import time

from fastapi import FastAPI, Response

# ---------------------------------------------------------------------------
# Logging — structured enough to demonstrate kubectl logs, simple enough to
# understand without a log-aggregation stack.
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
log = logging.getLogger("reliability-app")

# ---------------------------------------------------------------------------
# Application startup
# ---------------------------------------------------------------------------
APP_VERSION = "1.0.0"
START_TIME = time.time()

app = FastAPI(
    title="Reliability Lab App",
    description="Educational workload for Kubernetes reliability scenarios",
    version=APP_VERSION,
)

log.info("Application process started (version %s)", APP_VERSION)


# ---------------------------------------------------------------------------
# Helper — read configuration from environment variables so we can use a
# Kubernetes ConfigMap without baking values into the image.
# ---------------------------------------------------------------------------
def _get_env(key: str, default: str = "") -> str:
    """Return an environment variable, logging clearly if the default is used."""
    value = os.environ.get(key, default)
    if value == default and default != "":
        log.debug("Env %s not set; using default '%s'", key, default)
    return value


# ---------------------------------------------------------------------------
# Probe endpoints
# ---------------------------------------------------------------------------

@app.get("/startup", tags=["probes"])
def startup_probe():
    """
    Startup probe — called by Kubernetes until it succeeds, then never again.

    Purpose: give slow-starting containers time to initialise without
    triggering the liveness probe too early.  Once this returns 200, Kubernetes
    switches to the liveness probe.

    This implementation always returns 200 because our app starts instantly.
    In a real app you would check whether a database migration has finished.
    """
    uptime = round(time.time() - START_TIME, 2)
    return {"status": "started", "uptime_seconds": uptime}


@app.get("/health", tags=["probes"])
def liveness_probe():
    """
    Liveness probe — called repeatedly throughout the container lifetime.

    Purpose: detect deadlocks or corrupted state that prevent the application
    from making progress.  If this returns a non-2xx status, Kubernetes restarts
    the container.

    This implementation always returns 200 while the process is alive.
    In a real app you might check whether a background thread is still running.
    """
    return {"status": "alive", "version": APP_VERSION}


@app.get("/ready", tags=["probes"])
def readiness_probe(response: Response):
    """
    Readiness probe — called repeatedly; a failure removes the Pod from
    Service endpoints without restarting it.

    Purpose: signal that the container is able to accept traffic.  Use this
    when a dependency (cache warm-up, config load, external service) is not yet
    available.

    READY_TO_SERVE controls whether this endpoint succeeds.  Setting it to
    'false' via a ConfigMap change powers Scenario A without any code change.
    """
    ready = _get_env("READY_TO_SERVE", "true").lower()

    if ready != "true":
        # 503 Service Unavailable — Pod stays Running but exits Service rotation
        response.status_code = 503
        log.warning(
            "Readiness check FAILED — READY_TO_SERVE=%s "
            "(Pod will be removed from Service endpoints)",
            ready,
        )
        return {
            "status": "not_ready",
            "reason": "READY_TO_SERVE environment variable is not 'true'",
            "value": ready,
        }

    log.info("Readiness check OK")
    return {"status": "ready"}


# ---------------------------------------------------------------------------
# Application endpoint
# ---------------------------------------------------------------------------

@app.get("/", tags=["app"])
def root():
    """
    Main endpoint — returns version, configuration, and uptime.
    Used in smoke tests to confirm the application is responding.
    """
    return {
        "app": "kubernetes-workload-reliability-lab",
        "version": APP_VERSION,
        "uptime_seconds": round(time.time() - START_TIME, 2),
        "environment": _get_env("APP_ENV", "development"),
        "log_level": _get_env("LOG_LEVEL", "INFO"),
    }


@app.get("/metrics-info", tags=["observability"])
def metrics_info():
    """
    Documents which Prometheus metrics are exposed and how to access them.
    The actual /metrics endpoint is added by prometheus-fastapi-instrumentator
    at startup (see below).  This endpoint explains the setup for the lab.
    """
    return {
        "prometheus_endpoint": "/metrics",
        "note": (
            "Metrics are available at /metrics if prometheus-fastapi-instrumentator "
            "is installed.  In the lab, this requires the optional observability "
            "setup described in docs/setup.md."
        ),
    }


# ---------------------------------------------------------------------------
# Optional Prometheus instrumentation
# Install: pip install prometheus-fastapi-instrumentator
# If the package is not installed the application starts normally without it.
# ---------------------------------------------------------------------------
try:
    from prometheus_fastapi_instrumentator import Instrumentator  # type: ignore

    Instrumentator().instrument(app).expose(app)
    log.info("Prometheus instrumentation enabled at /metrics")
except ImportError:
    log.info(
        "prometheus-fastapi-instrumentator not installed; "
        "/metrics endpoint not available (this is expected in minimal installs)"
    )
