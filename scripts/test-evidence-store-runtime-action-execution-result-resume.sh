#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR=".tmp/test-runtime-action-execution-result-mock-resume"
DB_PATH=".tmp/test-evidence-store-runtime-action-execution-result-resume.sqlite"
RELEASE_ID="runtime-action-resume-preflight-manual-gate-smoke"

rm -f "$DB_PATH"

echo "===== generate resume runtime action execution result fixture ====="
bash scripts/test-runtime-action-execution-result-mock-resume.sh >/tmp/ssentinel-runtime-action-execution-result-resume-store-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-resume-store-source.log

echo "===== import into EvidenceStore ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$REPORT_DIR"

echo "===== search runtimeActionExecutionResult ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionExecutionResult \
  --release-id "$RELEASE_ID" \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-execution-result-resume-search.json

cat /tmp/ssentinel-runtime-action-execution-result-resume-search.json

echo "===== assert resume runtimeActionExecutionResult summary ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-resume-preflight-manual-gate-smoke"
data = json.loads(Path("/tmp/ssentinel-runtime-action-execution-result-resume-search.json").read_text(encoding="utf-8"))
items = data.get("items") or data.get("objects") or []
assert len(items) == 1, data

summary = items[0].get("summary") or {}
assert summary.get("objectType") == "runtimeActionExecutionResult", summary
assert summary.get("schemaVersion") == "runtime.action.execution.result/v1alpha1", summary
assert summary.get("runtimeActionExecutionResultId") == "raer-" + release_id, summary
assert summary.get("sourceRuntimeActionPreflightId") == "rap-" + release_id, summary
assert summary.get("requestedAction") == "RESUME_ROLLOUT", summary
assert summary.get("actionStatus") == "EXECUTION_SUCCEEDED", summary
assert summary.get("executionStatus") == "SUCCEEDED", summary
assert summary.get("verificationStatus") == "VERIFIED", summary
assert summary.get("pauseVerified") is False, summary
assert summary.get("resumeVerified") is True, summary
assert summary.get("postActionObserved") is True, summary
assert summary.get("desiredStateObserved") is True, summary
assert summary.get("afterObservationMode") == "live_readonly_rollout_get_after_action", summary
assert summary.get("commandMode") == "kubectl_patch_rollout_spec_paused_false", summary
assert summary.get("commandExitCode") == 0, summary
assert summary.get("didPause") is False, summary
assert summary.get("didResume") is True, summary
assert summary.get("attemptedKubernetesMutation") is True, summary
assert summary.get("mutatedKubernetes") is True, summary
assert summary.get("mutatedGitOps") is False, summary
assert summary.get("didModifyKubernetes") is True, summary
assert summary.get("didModifyGitOps") is False, summary
assert summary.get("willExecute") is True, summary
assert summary.get("rolloutName") == "demo-app", summary
assert summary.get("namespace") == "slo-rollout", summary

print("PASS evidence store runtime action execution result resume")
PY
