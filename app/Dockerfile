# syntax=docker/dockerfile:1
# ============================================================
# Multi-stage build for the Reliability Lab application
# ============================================================
#
# Stage 1 (builder): install Python dependencies into a virtual
# environment.  This keeps the final image free of build tools.
#
# Stage 2 (runtime): copy only the venv and the application code.
# We run as a non-root user (UID 1001) to satisfy the
# runAsNonRoot security policy in the Kubernetes manifest.
#
# Image: python:3.13-slim-bookworm
#   - python:3.13 — matches the local Python version (3.13.14)
#   - slim-bookworm — Debian Bookworm stripped of most apt packages,
#     giving a smaller attack surface than the full image.
#   - We pin the digest in production; here we pin the tag for
#     readability and note that digest pinning is documented in
#     docs/setup.md under "Supply-chain hardening".
# ============================================================

# ---- Stage 1: dependency builder ----
FROM python:3.13-slim-bookworm AS builder

WORKDIR /build

# Copy only the dependency file first so Docker layer caching skips
# re-installing packages when only application code changes.
COPY requirements.txt .

# Create an isolated virtual environment so we can copy it cleanly.
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


# ---- Stage 2: runtime image ----
FROM python:3.13-slim-bookworm AS runtime

# Security: create a dedicated non-root user.
# UID 1001 is arbitrary but avoids collision with common system UIDs.
# The Kubernetes manifest enforces runAsUser: 1001 and runAsNonRoot: true.
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid 1001 --no-create-home --shell /bin/false appuser

WORKDIR /app

# Copy the virtual environment from the builder stage.
COPY --from=builder /opt/venv /opt/venv

# Copy application code.
# Explicitly list what to copy so we don't accidentally include test files,
# .env files, or other development artifacts.
COPY main.py .

# Make the venv the active Python.
ENV PATH="/opt/venv/bin:$PATH"

# Expose the port uvicorn listens on.
# This is documentation only; the actual port binding happens in the
# Kubernetes Service and/or `docker run -p` command.
EXPOSE 8080

# Switch to non-root user.
USER appuser

# Health check for local `docker run` use.
# In Kubernetes, probes are defined in the manifest, not here.
# The HEALTHCHECK instruction is ignored by Kubernetes.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

# Run uvicorn on all interfaces so the Kubernetes Service can reach it.
# --workers 1: single worker is sufficient for the lab and keeps resource
#   usage predictable for Scenario B (resource pressure).
# --no-access-log: reduces noise; we use the /health and /ready log lines.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
