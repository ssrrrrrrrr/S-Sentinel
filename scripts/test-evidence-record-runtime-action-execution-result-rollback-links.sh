#!/usr/bin/env bash
set -euo pipefail

TEST_TMP=".tmp/test-runtime-action-execution-result-mock-rollback"
RELEASE_ID="runtime-action-rollback-execution-mock-smoke"
EVIDENCE_PATH="$TEST_TMP/release-evidence-$RELEASE_ID.json"

bash scripts/test-runtime-action-execution-result-mock-rollback.sh >/tmp/ssentinel-runtime-action-execution-result-rollback-record-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-rollback-record-source.log

cat > "$EVIDENCE_PATH" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "version": "v-runtime-action-execution-result-rollback-evidence",
  "generatedBy": "test-evidence-record-runtime-action-execution-result-rollback-links.sh",
  "generatedAt": "2026-05-27T10:30:00Z",
  "artifacts": {
    "runtimeActionExecutionResult": "runtime-action-execution-result-$RELEASE_ID.json"
  }
}
JSON

EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
bash scripts/build-evidence-record.sh "$EVIDENCE_PATH"

python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-rollback-execution-mock-smoke"
record = json.loads(Path(f".tmp/test-runtime-action-execution-result-mock-rollback/evidence-record-{release_id}.json").read_text(encoding="utf-8"))

execution = record.get("runtimeActionExecutionResult") or {}
links = record.get("links") or record.get("evidenceLinks") or {}
artifacts = record.get("artifacts") or {}
target = execution.get("rollbackTarget") or {}

assert links.get("runtimeActionExecutionResult", "").endswith(f"runtime-action-execution-result-{release_id}.json"), links
assert artifacts["runtimeActionExecutionResult"]["exists"] is True, artifacts.get("runtimeActionExecutionResult")

assert execution["runtimeActionExecutionResultId"] == "raer-" + release_id, execution
assert execution["requestedAction"] == "ROLLBACK_ROLLOUT", execution
assert execution["executionStatus"] == "SUCCEEDED", execution
assert execution["verificationStatus"] == "VERIFIED", execution
assert execution["commandMode"] == "kubectl_argo_rollouts_undo_to_revision", execution
assert execution["rollbackVerified"] is True, execution
assert execution["didRollback"] is True, execution
assert execution["didPause"] is False, execution
assert execution["didResume"] is False, execution
assert execution["didPromote"] is False, execution
assert execution["didAbort"] is False, execution
assert execution["mutatedKubernetes"] is True, execution
assert execution["mutatedGitOps"] is False, execution
assert target["targetRevision"] == 3, target
assert target["commandArgumentMode"] == "explicit_to_revision", target
assert execution["sourceRuntimeActionExecutionResult"].endswith(f"runtime-action-execution-result-{release_id}.json"), execution

print("PASS evidence record runtime action execution result rollback links")
PY
