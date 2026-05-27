#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p .tmp
bash scripts/test-runtime-action-execution-result-mock-rollback.sh > .tmp/test-runtime-action-execution-summary.log

python3 - <<'PY'
import json
from pathlib import Path

path = Path(".tmp/test-runtime-action-execution-result-mock-rollback/runtime-action-execution-result-runtime-action-rollback-execution-mock-smoke.json")
data = json.loads(path.read_text(encoding="utf-8"))

summary = data.get("executionSummary") or {}

assert summary["requestedAction"] == "ROLLBACK_ROLLOUT"
assert summary["didExecute"] is True
assert summary["willExecute"] is True
assert summary["verified"] is True
assert summary["verificationStatus"] == "VERIFIED"
assert summary["executionStatus"] == "SUCCEEDED"
assert summary["commandMode"] == "kubectl_argo_rollouts_undo_to_revision"
assert summary["mutationTarget"] == "kubernetes"
assert summary["mutatedKubernetes"] is True
assert summary["mutatedGitOps"] is False
assert summary["riskLevel"] == "high"

print("PASS runtime action execution summary contract")
PY
