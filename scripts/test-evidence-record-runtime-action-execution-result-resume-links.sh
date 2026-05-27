#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-runtime-action-execution-result-mock-resume"
RELEASE_ID="runtime-action-resume-preflight-manual-gate-smoke"

echo "===== generate resume runtime action execution result fixture ====="
bash scripts/test-runtime-action-execution-result-mock-resume.sh >/tmp/ssentinel-runtime-action-execution-result-resume-record-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-resume-record-source.log

cat > "$TEST_TMP/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-action-execution-result-resume-evidence",
  "generatedAt": "2026-05-27T06:06:06Z",
  "generatedBy": "test-evidence-record-runtime-action-execution-result-resume-links.sh",
  "releaseResult": "MANUAL_RUNTIME_ACTION",
  "policyDecision": "APPROVED",
  "finalAction": "RESUME_ROLLOUT",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-$RELEASE_ID.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-$RELEASE_ID.json",
    "runtimeActionRequest": "runtime-action-request-$RELEASE_ID.json",
    "runtimeActionPreflight": "runtime-action-preflight-$RELEASE_ID.json",
    "runtimeActionExecutionResult": "runtime-action-execution-result-$RELEASE_ID.json"
  },
  "safety": {
    "readOnly": false,
    "willExecute": true
  }
}
JSON

echo "===== build evidence record ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  scripts/build-evidence-record.sh "$TEST_TMP/release-evidence-$RELEASE_ID.json"

RECORD="$TEST_TMP/evidence-record-$RELEASE_ID.json"

echo "===== assert evidence record resume runtime action execution result links ====="
python3 - "$RECORD" "$RELEASE_ID" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release_id = sys.argv[2]

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}
execution = record.get("runtimeActionExecutionResult") or {}

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == release_id, record

assert links.get("runtimeActionExecutionResult", "").endswith(f"runtime-action-execution-result-{release_id}.json"), links
assert artifacts["runtimeActionExecutionResult"]["exists"] is True, artifacts.get("runtimeActionExecutionResult")

assert execution["runtimeActionExecutionResultId"] == "raer-" + release_id, execution
assert execution["mode"] == "controlled_runtime_action_result", execution
assert execution["sourceRuntimeActionPreflightId"] == "rap-" + release_id, execution
assert execution["sourceRuntimeActionRequestId"] == "rarq-" + release_id, execution
assert execution["requestedAction"] == "RESUME_ROLLOUT", execution
assert execution["actionStatus"] == "EXECUTION_SUCCEEDED", execution
assert execution["executionStatus"] == "SUCCEEDED", execution
assert execution["verificationStatus"] == "VERIFIED", execution
assert execution["pauseVerified"] is False, execution
assert execution["resumeVerified"] is True, execution
assert execution["postActionObserved"] is True, execution
assert execution["desiredStateObserved"] is True, execution
assert execution["afterObservationMode"] == "live_readonly_rollout_get_after_action", execution
assert execution["commandMode"] == "kubectl_patch_rollout_spec_paused_false", execution
assert execution["commandExitCode"] == 0, execution
assert execution["commandWillExecute"] is True, execution
assert execution["didPause"] is False, execution
assert execution["didResume"] is True, execution
assert execution["attemptedKubernetesMutation"] is True, execution
assert execution["mutatedKubernetes"] is True, execution
assert execution["mutatedGitOps"] is False, execution
assert execution["didModifyKubernetes"] is True, execution
assert execution["didModifyGitOps"] is False, execution
assert execution["preflightStatus"] == "PREFLIGHT_PASSED", execution
assert execution["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", execution
assert execution["finalExecuteEnabled"] is True, execution
assert execution["writeAllowed"] is True, execution
assert execution["rolloutName"] == "demo-app", execution
assert execution["namespace"] == "slo-rollout", execution
assert execution["service"] == "demo-app", execution
assert execution["env"] == "dev", execution
assert execution["sourceRuntimeActionPreflight"].endswith(f"runtime-action-preflight-{release_id}.json"), execution
assert execution["sourceRuntimeActionRequest"].endswith(f"runtime-action-request-{release_id}.json"), execution
assert execution["sourceRuntimeActionRecommendation"].endswith(f"runtime-action-recommendation-{release_id}.json"), execution
assert execution["sourceRuntimeActionExecutionResult"].endswith(f"runtime-action-execution-result-{release_id}.json"), execution
assert execution["guardrails"]["willExecute"] is True, execution
assert execution["guardrails"]["doesNotResume"] is False, execution
assert execution["guardrails"]["doesNotModifyGitOps"] is True, execution

assert record["coverage"]["total"] == 59, record["coverage"]

print("PASS evidence-record runtime action execution result resume links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
