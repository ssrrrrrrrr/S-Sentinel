#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p .tmp
bash scripts/test-runtime-action-execution-result-mock-rollback.sh > .tmp/test-runtime-action-risk-summary.log

python3 - <<'PY'
import json
from pathlib import Path

path = Path(".tmp/test-runtime-action-execution-result-mock-rollback/runtime-action-execution-result-runtime-action-rollback-execution-mock-smoke.json")
data = json.loads(path.read_text(encoding="utf-8"))

summary = data.get("riskSummary") or {}

assert summary["riskLevel"] == "high", summary
assert summary["requiresApproval"] is True, summary
assert summary["requiresFinalExecute"] is True, summary
assert summary["defaultOff"] is True, summary
assert summary["mutationTarget"] == "kubernetes", summary
assert summary["canMutateKubernetes"] is True, summary
assert summary["mutatedKubernetes"] is True, summary
assert summary["mutatesGitOps"] is False, summary

print("PASS runtime action risk summary contract")
PY
