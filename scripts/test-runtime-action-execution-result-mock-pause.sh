#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-execution-result-mock-pause"
RELEASE_ID="runtime-action-pause-execution-mock-smoke"

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
  && [ "$7" = "-p" ]; then
  echo "rollout.argoproj.io/demo-app patched"
  exit 0
fi
echo "unexpected kubectl args: $*" >&2
exit 2
MOCK
chmod +x "$TMP_DIR/fake-bin/kubectl"

echo "===== build gated preflight fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="$RELEASE_ID" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-runtime-action-execution-result-mock-pause/rollout-runtime-inspect-runtime-action-pause-execution-mock-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))
data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-$RELEASE_ID.json"

RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TMP_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TMP_DIR/runtime-action-recommendation-$RELEASE_ID.json"

python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-runtime-action-execution-result-mock-pause/runtime-action-request-runtime-action-pause-execution-mock-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))
data["request"]["requestStatus"] = "READY_FOR_PREFLIGHT"
data["request"]["lifecycleStage"] = "READY_FOR_PREFLIGHT"
data["approval"]["status"] = "APPROVED"
data["approval"]["approved"] = True
data["approval"]["approvalDecision"] = "APPROVED_FOR_LOW_RISK_PAUSE"
p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PAUSE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-preflight.sh "$TMP_DIR/runtime-action-request-$RELEASE_ID.json"

echo "===== execute controlled pause through mock kubectl ====="
PATH="$TMP_DIR/fake-bin:$PATH" \
S_SENTINEL_MOCK_KUBECTL_LOG="$TMP_DIR/kubectl.log" \
S_SENTINEL_RUNTIME_EXECUTION_ENABLED=true \
S_SENTINEL_ALLOW_RUNTIME_PAUSE=true \
S_SENTINEL_RUNTIME_ACTION_APPROVED=true \
S_SENTINEL_RUNTIME_PAUSE_EXECUTE=true \
RUNTIME_ACTION_EXECUTION_RESULT_OUTPUT_DIR="$TMP_DIR" \
bash scripts/build-runtime-action-execution-result.sh "$TMP_DIR/runtime-action-preflight-$RELEASE_ID.json"

echo "===== assert mock pause execution result ====="
python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-pause-execution-mock-smoke"
doc = json.loads(Path(f".tmp/test-runtime-action-execution-result-mock-pause/runtime-action-execution-result-{release_id}.json").read_text(encoding="utf-8"))

assert doc["action"]["requestedAction"] == "PAUSE_ROLLOUT", doc
assert doc["action"]["actionStatus"] == "EXECUTION_SUCCEEDED", doc
assert doc["action"]["commandWillExecute"] is True, doc
assert doc["action"]["commandExitCode"] == 0, doc
assert "patched" in doc["action"]["commandStdout"], doc

assert doc["writeGate"]["preflightPassed"] is True, doc
assert doc["writeGate"]["globalGateEnabled"] is True, doc
assert doc["writeGate"]["operationGateEnabled"] is True, doc
assert doc["writeGate"]["approvalGateEnabled"] is True, doc
assert doc["writeGate"]["finalExecuteEnabled"] is True, doc
assert doc["writeGate"]["writeAllowed"] is True, doc
assert doc["writeGate"]["willExecute"] is True, doc

assert doc["result"]["executionStatus"] == "SUCCEEDED", doc
assert doc["result"]["didPause"] is True, doc
assert doc["result"]["attemptedKubernetesMutation"] is True, doc
assert doc["result"]["mutatedKubernetes"] is True, doc
assert doc["result"]["mutatedGitOps"] is False, doc
assert doc["result"]["willExecute"] is True, doc

assert doc["receipt"]["didPause"] is True, doc
assert doc["receipt"]["attemptedModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyKubernetes"] is True, doc
assert doc["receipt"]["didModifyGitOps"] is False, doc

assert doc["guardrails"]["willExecute"] is True, doc
assert doc["guardrails"]["doesNotPause"] is False, doc
assert doc["guardrails"]["doesNotModifyKubernetes"] is False, doc
assert doc["guardrails"]["doesNotModifyGitOps"] is True, doc
assert doc["guardrails"]["doesNotCommitOrPush"] is True, doc

log = Path(".tmp/test-runtime-action-execution-result-mock-pause/kubectl.log").read_text(encoding="utf-8")
assert "-n slo-rollout patch rollout demo-app --type=merge -p" in log, log

print("PASS runtime action execution result mock pause")
PY
