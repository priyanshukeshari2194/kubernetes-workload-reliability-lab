# Test Results Template
# =====================
# Use this template to record evidence when running each lab scenario.
# Fill in every field yourself — do not fabricate results.
# An incomplete entry is honest; a fabricated entry is not useful.
#
# Copy this file for each test session:
#   cp tests/RESULTS_TEMPLATE.md tests/results/YYYY-MM-DD-<scenario>.md

---

## Test Session Record

| Field          | Value |
|----------------|-------|
| Date           | YYYY-MM-DD |
| Tester         | (your name) |
| Host OS        | Windows 11 (WSL2 Ubuntu 22.04) |
| kind version   | (output of `kind version`) |
| kubectl version| (output of `kubectl version --client`) |
| Docker version | (output of `docker version`) |
| Cluster name   | reliability-lab |
| Namespace      | reliability-lab |
| Image tag      | reliability-app:1.0.0 |

---

## Baseline Health Check

**Commands run:**
```bash
kubectl get pods -n reliability-lab
kubectl get endpoints reliability-app-svc -n reliability-lab
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

**Expected output (pods):**
```
NAME                              READY   STATUS    RESTARTS   AGE
reliability-app-xxxx-yyy          2/2     Running   0          2m
```

**Actual output:**
```
(paste here)
```

**Result:** [ ] PASS  [ ] FAIL  [ ] SKIPPED (reason: _________)

---

## Scenario A — Readiness Probe Failure

**Pre-condition:** Baseline app deployed and healthy.

**Steps:**
```bash
make scenario-a
# Wait 30 seconds
kubectl get pods -n reliability-lab
kubectl describe pod -l app.kubernetes.io/name=reliability-app -n reliability-lab
kubectl get endpoints reliability-app-svc -n reliability-lab
```

**Expected: Pod status (after ~30s)**
```
NAME                              READY   STATUS    RESTARTS   AGE
reliability-app-xxxx-yyy          0/1     Running   0          Xs
```

**Actual Pod status:**
```
(paste here)
```

**Expected: describe pod events section**
```
Readiness probe failed: HTTP probe failed with statuscode: 503
```

**Actual events:**
```
(paste here)
```

**Expected: endpoints (no Pod IPs listed)**
```
NAME                   ENDPOINTS   AGE
reliability-app-svc    <none>      Xm
```

**Actual endpoints:**
```
(paste here)
```

**Recovery steps:**
```bash
make scenario-a-reset
kubectl get pods -n reliability-lab -w
kubectl get endpoints reliability-app-svc -n reliability-lab
```

**Recovery result:** [ ] PASS  [ ] FAIL

---

## Scenario B — Resource Pressure (OOMKill)

**Pre-condition:** Baseline app deployed. Scenario A reset.

**Steps:**
```bash
make scenario-b
# Watch for OOMKilled
kubectl get pods -n reliability-lab -w
kubectl describe pod -l lab.scenario=b-resource-pressure -n reliability-lab
```

**Expected: Pod status (after ~60s)**
```
NAME             READY   STATUS      RESTARTS   AGE
memory-hog-xxx   0/1     OOMKilled   1          65s
# then after backoff:
memory-hog-xxx   0/1     CrashLoopBackOff  2    90s
```

**Actual Pod status:**
```
(paste here)
```

**Expected: describe pod Last State**
```
Last State:  Terminated
  Reason:    OOMKilled
  Exit Code: 137
```

**Actual Last State:**
```
(paste here)
```

**kubectl top pods output (requires metrics-server):**
```
(paste here, or "metrics-server not available")
```

**Recovery steps:**
```bash
make scenario-b-reset
kubectl get pods -n reliability-lab  # memory-hog should be gone
```

**Recovery result:** [ ] PASS  [ ] FAIL

---

## Scenario C — Bad Rollout and Recovery

**Pre-condition:** Baseline app deployed. Scenarios A and B reset.

**Steps:**
```bash
make scenario-c
kubectl rollout status deployment/reliability-app -n reliability-lab
kubectl get pods -n reliability-lab
kubectl rollout history deployment/reliability-app -n reliability-lab
kubectl describe pod -l app.kubernetes.io/version=does-not-exist-999 -n reliability-lab
```

**Expected: rollout status (stuck)**
```
Waiting for deployment "reliability-app" rollout to finish:
1 out of 2 new replicas have been updated...
```

**Actual rollout status:**
```
(paste here)
```

**Expected: pod status (new pod stuck)**
```
NAME                              READY   STATUS              RESTARTS   AGE
reliability-app-<old>-xxx         1/1     Running             0          5m
reliability-app-<new>-yyy         0/1     ErrImageNeverPull   0          30s
```

**Actual pod status:**
```
(paste here)
```

**Expected: rollout history (at least 2 revisions)**
```
REVISION  CHANGE-CAUSE
1         Initial deployment — baseline application
2         Scenario C — intentionally bad image tag (lab demonstration)
```

**Actual rollout history:**
```
(paste here)
```

**Recovery steps:**
```bash
make scenario-c-reset
kubectl rollout status deployment/reliability-app -n reliability-lab
curl http://localhost:8080/health
```

**Recovery result:** [ ] PASS  [ ] FAIL

---

## Unit Tests

```bash
python -m pytest tests/unit/ -v
```

**Result:** ___ / 15 passed

**Output:**
```
(paste full pytest output)
```

---

## Manifest Validation

```bash
python tests/validate_manifests.py
```

**Expected:** 10 passed, 1 warning (memory-hog no probes), 0 errors

**Actual:**
```
(paste output)
```

---

## Notes and Deviations

(Record anything that did not match expected output, workarounds applied,
or features not tested in this session.)

---

## Tester Sign-off

I ran the commands above personally on the hardware described.
The results recorded above are accurate to the best of my knowledge.
Untested sections are marked SKIPPED.

Signed: _________________ Date: _________________
