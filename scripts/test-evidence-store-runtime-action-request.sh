#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR=".tmp/test-evidence-store-runtime-action-request-report"
DB_PATH=".tmp/test-evidence-store-runtime-action-request.sqlite"

rm -rf "$REPORT_DIR"
rm -f "$DB_PATH"
mkdir -p "$REPORT_DIR"

echo "===== build review source inspect ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-action-review-request-store-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$REPORT_DIR"

echo "===== build review recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$REPORT_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$REPORT_DIR/rollout-runtime-inspect-runtime-action-review-request-store-smoke.json"

echo "===== build review request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$REPORT_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$REPORT_DIR/runtime-action-recommendation-runtime-action-review-request-store-smoke.json"

echo "===== build failed source inspect ====="
cp \
  "$REPORT_DIR/rollout-runtime-inspect-runtime-action-review-request-store-smoke.json" \
  "$REPORT_DIR/rollout-runtime-inspect-runtime-action-pause-request-store-smoke.json"

python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-evidence-store-runtime-action-request-report/rollout-runtime-inspect-runtime-action-pause-request-store-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))

data["rolloutRuntimeInspectId"] = "rti-runtime-action-pause-request-store-smoke"
data["release"]["releaseId"] = "runtime-action-pause-request-store-smoke"
data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

p.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "===== build pause recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$REPORT_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$REPORT_DIR/rollout-runtime-inspect-runtime-action-pause-request-store-smoke.json"

echo "===== build pause request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$REPORT_DIR" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$REPORT_DIR/runtime-action-recommendation-runtime-action-pause-request-store-smoke.json"

echo "===== init db ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null

echo "===== import runtime action request fixtures ====="
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$REPORT_DIR"

echo "===== search review request ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionRequest \
  --release-id runtime-action-review-request-store-smoke \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-review-request-search.json
cat /tmp/ssentinel-runtime-action-review-request-search.json

echo "===== search pause request ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionRequest \
  --release-id runtime-action-pause-request-store-smoke \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-pause-request-search.json
cat /tmp/ssentinel-runtime-action-pause-request-search.json

echo "===== assert EvidenceStore summaries ====="
python3 - <<'PY'
import json
from pathlib import Path

def first_summary(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    items = data.get("items") or data.get("objects") or []
    assert items, data
    return items[0].get("summary") or {}

review = first_summary("/tmp/ssentinel-runtime-action-review-request-search.json")
pause = first_summary("/tmp/ssentinel-runtime-action-pause-request-search.json")

assert review["objectType"] == "runtimeActionRequest", review
assert review["schemaVersion"] == "runtime.action.request/v1alpha1", review
assert review["runtimeActionRequestId"] == "rarq-runtime-action-review-request-store-smoke", review
assert review["requestedAction"] == "REQUIRE_REVIEW", review
assert review["requestStatus"] == "REVIEW_REQUIRED", review
assert review["lifecycleStage"] == "WAITING_REVIEW", review
assert review["recommendationStatus"] == "REVIEW_RECOMMENDED", review
assert review["recommendedAction"] == "REQUIRE_REVIEW", review
assert review["approvalRequired"] is True, review
assert review["readyToExecute"] is False, review
assert review["approvalStatus"] == "NOT_APPROVED", review
assert review["rolloutName"] == "demo-app", review
assert review["rolloutPhase"] == "Progressing", review
assert review["analysisStatus"] == "Running", review
assert review["sourceRuntimeActionRecommendationId"] == "rar-runtime-action-review-request-store-smoke", review
assert review["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-review-request-store-smoke", review
assert review["requestOnly"] is True, review
assert review["readOnly"] is True, review
assert review["willExecute"] is False, review
assert review["doesNotPause"] is True, review
assert review["doesNotModifyKubernetes"] is True, review

assert pause["objectType"] == "runtimeActionRequest", pause
assert pause["schemaVersion"] == "runtime.action.request/v1alpha1", pause
assert pause["runtimeActionRequestId"] == "rarq-runtime-action-pause-request-store-smoke", pause
assert pause["requestedAction"] == "PAUSE_ROLLOUT", pause
assert pause["requestStatus"] == "PENDING_APPROVAL", pause
assert pause["lifecycleStage"] == "WAITING_APPROVAL", pause
assert pause["riskLevel"] == "high", pause
assert pause["recommendationStatus"] == "ACTION_RECOMMENDED", pause
assert pause["recommendedAction"] == "PAUSE_ROLLOUT", pause
assert pause["allowedToRequest"] is True, pause
assert pause["approvalRequired"] is True, pause
assert pause["readyToExecute"] is False, pause
assert pause["approvalStatus"] == "NOT_APPROVED", pause
assert pause["approved"] is False, pause
assert pause["rolloutPhase"] == "Degraded", pause
assert pause["analysisStatus"] == "Failed", pause
assert pause["sourceRuntimeActionRecommendationId"] == "rar-runtime-action-pause-request-store-smoke", pause
assert pause["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-pause-request-store-smoke", pause
assert pause["requestOnly"] is True, pause
assert pause["willExecute"] is False, pause
assert pause["doesNotPause"] is True, pause
assert pause["doesNotModifyKubernetes"] is True, pause

print("PASS evidence-store runtime action request")
PY
