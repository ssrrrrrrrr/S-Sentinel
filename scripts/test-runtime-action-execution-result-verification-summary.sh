#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p .tmp
bash scripts/test-runtime-action-execution-result-mock-rollback.sh > .tmp/test-runtime-action-verification-summary.log

python3 - <<'PY'
import json
from pathlib import Path

path = Path(".tmp/test-runtime-action-execution-result-mock-rollback/runtime-action-execution-result-runtime-action-rollback-execution-mock-smoke.json")
data = json.loads(path.read_text(encoding="utf-8"))

summary = data.get("verificationSummary") or {}

assert summary["status"] == "VERIFIED", summary
assert summary["verified"] is True, summary
assert summary["commandSucceeded"] is True, summary
assert summary["postActionObserved"] is True, summary
assert summary["desiredStateObserved"] is True, summary
assert summary["actionVerified"] is True, summary
assert summary["blockingReasonCount"] == 0, summary
assert summary["warningReasonCount"] == 0, summary

print("PASS runtime action verification summary contract")
PY
