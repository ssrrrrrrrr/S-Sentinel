#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p .tmp
bash scripts/test-runtime-action-execution-result-mock-rollback.sh > .tmp/test-runtime-action-gate-summary.log

python3 - <<'PY'
import json
from pathlib import Path

path = Path(".tmp/test-runtime-action-execution-result-mock-rollback/runtime-action-execution-result-runtime-action-rollback-execution-mock-smoke.json")
data = json.loads(path.read_text(encoding="utf-8"))

gate = data.get("gateSummary") or {}

assert gate["preflight"] == "passed", gate
assert gate["global"] == "enabled", gate
assert gate["operation"] == "enabled", gate
assert gate["approval"] == "enabled", gate
assert gate["finalExecute"] == "enabled", gate
assert gate["overall"] == "EXECUTION_SUCCEEDED", gate
assert gate["writeAllowed"] is True, gate
assert gate["willExecute"] is True, gate

print("PASS runtime action gate summary contract")
PY
