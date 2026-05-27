#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-runtime-action-execution-result-mock-pause"
RELEASE_ID="runtime-action-pause-execution-mock-smoke"

echo "===== generate runtime action execution result fixture ====="
bash scripts/test-runtime-action-execution-result-mock-pause.sh >/tmp/ssentinel-runtime-action-execution-result-record-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-record-source.log

cat > "$TEST_TMP/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-action-execution-result-evidence",
  "generatedAt": "2026-05-27T05:05:05Z",
  "generatedBy": "test-evidence-record-runtime-action-execution-result-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
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

echo "===== assert evidence record runtime action execution result links ====="
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
assert execution["requestedAction"] == "PAUSE_ROLLOUT", execution
assert execution["actionStatus"] == "EXECUTION_SUCCEEDED", execution
assert execution["executionStatus"] == "SUCCEEDED", execution
assert execution["commandMode"] == "kubectl_patch_rollout_spec_paused", execution
assert execution["commandExitCode"] == 0, execution
assert execution["commandWillExecute"] is True, execution
assert execution["didPause"] is True, execution
assert execution["attemptedKubernetesMutation"] is True, execution
assert execution["mutatedKubernetes"] is True, execution
assert execution["mutatedGitOps"] is False, execution
assert execution["didModifyKubernetes"] is True, execution
assert execution["didModifyGitOps"] is False, execution
assert execution["executorName"] == "runtime-pause-executor", execution
assert execution["executorAdapter"] == "runtime-pause", execution
assert execution["preflightStatus"] == "PREFLIGHT_PASSED", execution
assert execution["eligibilityStatus"] == "ELIGIBLE_FOR_CONTROLLED_EXECUTOR", execution
assert execution["finalExecuteEnabled"] is True, execution
assert execution["writeAllowed"] is True, execution
assert execution["rolloutName"] == "demo-app", execution
assert execution["namespace"] == "slo-rollout", execution
assert execution["service"] == "demo-app", execution
assert execution["env"] == "dev", execution
assert execution["rolloutPhase"] == "Degraded", execution
assert execution["analysisStatus"] == "Failed", execution
assert execution["sourceRuntimeActionPreflight"].endswith(f"runtime-action-preflight-{release_id}.json"), execution
assert execution["sourceRuntimeActionRequest"].endswith(f"runtime-action-request-{release_id}.json"), execution
assert execution["sourceRuntimeActionRecommendation"].endswith(f"runtime-action-recommendation-{release_id}.json"), execution
assert execution["sourceRolloutRuntimeInspect"].endswith(f"rollout-runtime-inspect-{release_id}.json"), execution
assert execution["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, execution
assert execution["sourceRuntimeActionExecutionResult"].endswith(f"runtime-action-execution-result-{release_id}.json"), execution
assert execution["guardrails"]["willExecute"] is True, execution
assert execution["guardrails"]["doesNotModifyGitOps"] is True, execution

assert record["coverage"]["total"] == 59, record["coverage"]

print("PASS evidence-record runtime action execution result links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
