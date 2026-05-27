#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-execution-result-mock-resume"
PREFLIGHT_TMP_DIR=".tmp/test-runtime-action-preflight-resume-manual-gate"
RELEASE_ID="runtime-action-resume-preflight-manual-gate-smoke"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/fake-bin"

cat > "$TMP_DIR/fake-bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "${S_SENTINEL_MOCK_KUBECTL_LOG}"

if [ "$#" -ge 8 ] \
  && [ "$1" = "-n" ] \
  && [ "$2" = "slo-rollout" ] \
  && [ "$3" = "patch" ] \
  && [ "$4" = "rollout" ] \
  && [ "$5" = "demo-app" ] \
  && [ "$6" = "--type=merge" ] \
  && [ "$7" = "-p" ] \
  && [ "$8" = '{"spec":{"paused":false}}' ]; then
  echo "rollout.argoproj.io/demo-app patched"
  exit 0
fi

if [ "$#" -eq 7 ] \
  && [ "$1" = "-n" ] \
  && [ "$2" = "slo-rollout" ] \
  && [ "$3" = "get" ] \
  && [ "$4" = "rollout" ] \
  && [ "$5" = "demo-app" ] \
  && [ "$6" = "-o" ] \
  && [ "$7" = "json" ]; then
  cat <<'JSON'
{
  "metadata": {
    "name": "demo-app",
    "namespace": "slo-rollout"
  },
  "spec": {
    "replicas": 3,
    "paused": false
  },
  "status": {
    "phase": "Healthy",
    "currentStepIndex": 2,
    "replicas": 3,
    "readyReplicas": 3,
    "availableReplicas": 3,
    "observedGeneration": 13,
    "conditions": [
      {
        "type": "Paused",
        "status": "False",
        "reason": "RolloutResumed"
      },
      {
        "type": "Healthy",
        "status": "True",
        "reason": "RolloutHealthy"
      }
    ]
  }
}
JSON
  exit 0
fi

echo "unexpected kubectl args: $*" >&2
exit 2
MOCK
chmod +x "$TMP_DIR/fake-bin/kubectl"

echo "===== build source resume preflight fixture ====="
bash scripts/test-runtime-action-preflight-resume-manual-gate.sh

echo "===== execute controlled resume through mock kubectl ====="
PATH="$TMP_DIR/fake-bin:$PATH" \
S_SENTINEL_MOCK_KUBECTL_LOG="$TMP_DIR/kubectl.log" \
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_RESUME=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
S_SENTINEL_RUNTIME_RESUME_EXECUTE=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-execution-result.sh "$PREFLIGHT_TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

echo "===== assert mock resume execution result ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-resume-preflight-manual-gate-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-execution-result-mock-resume/runtime-action-execution-result-{release_id}.json").read_text(encoding="utf-8"))

assert doc["action"]["requestedAction"] == "RESUME_ROLLOUT", doc
assert doc["action"]["supportedAction"] is True, doc
assert doc["action"]["actionStatus"] == "EXECUTION_SUCCEEDED", doc
assert doc["action"]["commandWillExecute"] is True, doc
assert doc["action"]["commandExitCode"] == 0, doc
assert doc["action"]["commandMode"] == "kubectl_patch_rollout_spec_paused_false", doc
assert "patched" in doc["action"]["commandStdout"], doc
assert '{"spec":{"paused":false}}' in doc["action"]["commandPreviewArgs"], doc

assert doc["writeGate"]["preflightPassed"] is True, doc
assert doc["writeGate"]["globalGateEnabled"] is True, doc
assert doc["writeGate"]["operationGateEnv"] == "S_SENTINEL_ALLOW_RUNTIME_RESUME", doc
assert doc["writeGate"]["operationGateEnabled"] is True, doc
assert doc["writeGate"]["resumeGateEnabled"] is True, doc
assert doc["writeGate"]["approvalGateEnabled"] is True, doc
assert doc["writeGate"]["finalExecuteEnv"] == "S_SENTINEL_RUNTIME_RESUME_EXECUTE", doc
assert doc["writeGate"]["finalExecuteEnabled"] is True, doc
assert doc["writeGate"]["operation"] == "RESUME_ROLLOUT", doc
assert doc["writeGate"]["writeAllowed"] is True, doc
assert doc["writeGate"]["willExecute"] is True, doc

assert doc["afterSnapshot"]["observationMode"] == "live_readonly_rollout_get_after_action", doc
assert doc["afterSnapshot"]["postActionRolloutGetAttempted"] is True, doc
assert doc["afterSnapshot"]["postActionRolloutGetSucceeded"] is True, doc
assert doc["afterSnapshot"]["paused"] is False, doc
assert doc["afterSnapshot"]["specPaused"] is False, doc
assert doc["afterSnapshot"]["statusPaused"] is False, doc
assert doc["afterSnapshot"]["phase"] == "Healthy", doc

verification = doc["postActionVerification"]
assert verification["verificationType"] == "runtime_action_post_action_verification", doc
assert verification["verificationStatus"] == "VERIFIED", doc
assert verification["requestedAction"] == "RESUME_ROLLOUT", doc
assert verification["commandSucceeded"] is True, doc
assert verification["postActionObserved"] is True, doc
assert verification["desiredStateObserved"] is True, doc
assert verification["pauseVerified"] is False, doc
assert verification["resumeVerified"] is True, doc
assert verification["expectedPaused"] is False, doc
assert verification["observedPaused"] is False, doc
assert verification["observedSpecPaused"] is False, doc
assert verification["observedStatusPaused"] is False, doc
assert verification["blockingReasons"] == [], doc
assert verification["warningReasons"] == [], doc

assert doc["result"]["executionStatus"] == "SUCCEEDED", doc
assert doc["result"]["actionStatus"] == "EXECUTION_SUCCEEDED", doc
assert doc["result"]["requestedAction"] == "RESUME_ROLLOUT", doc
assert doc["result"]["verificationStatus"] == "VERIFIED", doc
assert doc["result"]["pauseVerified"] is False, doc
assert doc["result"]["resumeVerified"] is True, doc
assert doc["result"]["postActionObserved"] is True, doc
assert doc["result"]["desiredStateObserved"] is True, doc
assert doc["result"]["didPause"] is False, doc
assert doc["result"]["didResume"] is True, doc
assert doc["result"]["attemptedKubernetesMutation"] is True, doc
assert doc["result"]["mutatedKubernetes"] is True, doc
assert doc["result"]["mutatedGitOps"] is False, doc
assert doc["result"]["willExecute"] is True, doc

assert doc["receipt"]["didPause"] is False, doc
assert doc["receipt"]["didResume"] is True, doc
assert doc["receipt"]["verificationStatus"] == "VERIFIED", doc
assert doc["receipt"]["pauseVerified"] is False, doc
assert doc["receipt"]["resumeVerified"] is True, doc
assert doc["receipt"]["attemptedModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyGitOps"] is False, doc

assert doc["guardrails"]["willExecute"] is True, doc
assert doc["guardrails"]["postActionVerified"] is True, doc
assert doc["guardrails"]["doesNotPause"] is True, doc
assert doc["guardrails"]["doesNotResume"] is False, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is False, doc
assert doc["guardrails"]["doesNotModifyGitOps"] is True, doc
assert doc["guardrails"]["doesNotCommitOrPush"] is True, doc

log = Path(".tmp/test-runtime-action-execution-result-mock-resume/kubectl.log").read_text(encoding="utf-8")
assert "-n slo-rollout patch rollout demo-app --type=merge -p {\"spec\":{\"paused\":false}}" in log, log
assert "-n slo-rollout get rollout demo-app -o json" in log, log

print("PASS runtime action execution result mock resume")
PY
