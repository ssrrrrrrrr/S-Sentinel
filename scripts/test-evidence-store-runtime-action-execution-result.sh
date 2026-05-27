#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR=".tmp/test-runtime-action-execution-result-mock-pause"
DB_PATH=".tmp/test-evidence-store-runtime-action-execution-result.sqlite"
RELEASE_ID="runtime-action-pause-execution-mock-smoke"

rm -f "$DB_PATH"

echo "===== generate runtime action execution result fixture ====="
bash scripts/test-runtime-action-execution-result-mock-pause.sh >/tmp/ssentinel-runtime-action-execution-result-store-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-store-source.log

echo "===== import into EvidenceStore ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$REPORT_DIR"

echo "===== search runtimeActionExecutionResult ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionExecutionResult \
  --release-id "$RELEASE_ID" \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-execution-result-search.json

cat /tmp/ssentinel-runtime-action-execution-result-search.json

echo "===== assert runtimeActionExecutionResult summary ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-pause-execution-mock-smoke"
data = json.loads(Path("/tmp/ssentinel-runtime-action-execution-result-search.json").read_text(encoding="utf-8"))
items = data.get("items") or data.get("objects") or []
assert len(items) == 1, data

summary = items[0].get("summary") or {}
assert summary.get("objectType") == "runtimeActionExecutionResult", summary
assert summary.get("schemaVersion") == "runtime.action.execution.result/v1alpha1", summary
assert summary.get("runtimeActionExecutionResultId") == "raer-" + release_id, summary
assert summary.get("sourceRuntimeActionPreflightId") == "rap-" + release_id, summary
assert summary.get("requestedAction") == "PAUSE_ROLLOUT", summary
assert summary.get("actionStatus") == "EXECUTION_SUCCEEDED", summary
assert summary.get("executionStatus") == "SUCCEEDED", summary
assert summary.get("commandMode") == "kubectl_patch_rollout_spec_paused", summary
assert summary.get("commandExitCode") == 0, summary
assert summary.get("didPause") is True, summary
assert summary.get("attemptedKubernetesMutation") is True, summary
assert summary.get("mutatedKubernetes") is True, summary
assert summary.get("mutatedGitOps") is False, summary
assert summary.get("didModifyKubernetes") is True, summary
assert summary.get("didModifyGitOps") is False, summary
assert summary.get("willExecute") is True, summary
assert summary.get("rolloutName") == "demo-app", summary
assert summary.get("namespace") == "slo-rollout", summary

print("PASS evidence store runtime action execution result")
PY
