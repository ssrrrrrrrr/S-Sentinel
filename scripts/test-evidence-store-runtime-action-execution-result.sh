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
assert summary.get("verificationStatus") == "VERIFIED", summary
assert summary.get("pauseVerified") is True, summary
assert summary.get("resumeVerified") is False, summary
assert summary.get("postActionObserved") is True, summary
assert summary.get("desiredStateObserved") is True, summary
assert summary.get("afterObservationMode") == "live_readonly_rollout_get_after_action", summary
assert summary.get("commandMode") == "kubectl_patch_rollout_spec_paused", summary
assert summary.get("commandExitCode") == 0, summary
assert summary.get("didPause") is True, summary
assert summary.get("didResume") is False, summary
assert summary.get("attemptedKubernetesMutation") is True, summary
assert summary.get("mutatedKubernetes") is True, summary
assert summary.get("mutatedGitOps") is False, summary
assert summary.get("didModifyKubernetes") is True, summary
assert summary.get("didModifyGitOps") is False, summary
assert summary.get("willExecute") is True, summary
assert summary.get("rolloutName") == "demo-app", summary
assert summary.get("namespace") == "slo-rollout", summary

actor = summary.get("actorBoundary") or {}
assert actor.get("boundaryVersion") == "runtime.action.actor-boundary/v1alpha1", summary
assert summary.get("actorRuntimeIdentity") == "local-shell-operator", summary
assert summary.get("actorKubernetesIdentity") == "kubectl-current-context", summary
assert summary.get("watcherRbacMode") == "read_only_get_list_watch", summary
assert summary.get("watcherCanMutateKubernetes") is False, summary
assert actor.get("rbacBoundary", {}).get("watcherCanMutateKubernetes") is False, summary
assert actor.get("rbacBoundary", {}).get("executorWasAllowedToMutateKubernetes") is True, summary

recovery = summary.get("recoveryBoundary") or {}
assert recovery.get("boundaryVersion") == "runtime.action.recovery-boundary/v1alpha1", summary
assert summary.get("manualRetryAllowed") is False, summary
assert summary.get("recoveryFailureMode") == "none", summary
assert recovery.get("failureRecovery", {}).get("executionStatus") == "SUCCEEDED", summary
assert recovery.get("failureRecovery", {}).get("failureMode") == "none", summary
assert recovery.get("failureRecovery", {}).get("recoveryRequired") is False, summary

safety = summary.get("executionSafetyBoundary") or {}
assert safety.get("boundaryVersion") == "runtime.action.execution-safety-boundary/v1alpha1", summary
assert summary.get("executionDefaultOff") is True, summary
assert summary.get("executionSafetyRiskLevel") == "medium_high", summary
assert summary.get("executionDirectExecutionAllowed") is True, summary
assert summary.get("executionSafetyBlockingReasons") == [], summary
assert safety.get("defaultPolicy", {}).get("defaultOff") is True, summary
assert safety.get("operationRisk", {}).get("requestedAction") == "PAUSE_ROLLOUT", summary
assert safety.get("operationRisk", {}).get("runtimeMutatingAction") is True, summary
assert safety.get("operationRisk", {}).get("highRiskAction") is False, summary
assert safety.get("gateMatrix", {}).get("globalGateEnabled") is True, summary
assert safety.get("gateMatrix", {}).get("operationGateEnabled") is True, summary
assert safety.get("gateMatrix", {}).get("approvalGateEnabled") is True, summary
assert safety.get("gateMatrix", {}).get("finalExecuteEnabled") is True, summary
assert safety.get("safetyDecision", {}).get("allRuntimeGatesEnabled") is True, summary
assert safety.get("safetyDecision", {}).get("directExecutionAllowed") is True, summary
assert safety.get("safetyDecision", {}).get("willExecute") is True, summary

print("PASS evidence store runtime action execution result")
PY
