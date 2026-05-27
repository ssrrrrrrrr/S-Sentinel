#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR=".tmp/test-evidence-store-runtime-action-recommendation-report"
DB_PATH=".tmp/test-evidence-store-runtime-action-recommendation.sqlite"

rm -rf "$REPORT_DIR"
rm -f "$DB_PATH"
mkdir -p "$REPORT_DIR"

echo "===== build review source inspect ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-action-review-store-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$REPORT_DIR"

echo "===== build review recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$REPORT_DIR" \
bash scripts/build-runtime-action-recommendation.sh "$REPORT_DIR/rollout-runtime-inspect-runtime-action-review-store-smoke.json"

echo "===== build failed source inspect ====="
cp \
  "$REPORT_DIR/rollout-runtime-inspect-runtime-action-review-store-smoke.json" \
  "$REPORT_DIR/rollout-runtime-inspect-runtime-action-failed-store-smoke.json"

python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-evidence-store-runtime-action-recommendation-report/rollout-runtime-inspect-runtime-action-failed-store-smoke.json")
data = json.loads(p.read_text(encoding="utf-8"))

data["rolloutRuntimeInspectId"] = "rti-runtime-action-failed-store-smoke"
data["release"]["releaseId"] = "runtime-action-failed-store-smoke"
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
bash scripts/build-runtime-action-recommendation.sh "$REPORT_DIR/rollout-runtime-inspect-runtime-action-failed-store-smoke.json"

echo "===== init db ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null

echo "===== import runtime action recommendation fixtures ====="
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$REPORT_DIR"

echo "===== search review recommendation ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionRecommendation \
  --release-id runtime-action-review-store-smoke \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-review-search.json
cat /tmp/ssentinel-runtime-action-review-search.json

echo "===== search pause recommendation ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionRecommendation \
  --release-id runtime-action-failed-store-smoke \
  --limit 10 \
  >/tmp/ssentinel-runtime-action-pause-search.json
cat /tmp/ssentinel-runtime-action-pause-search.json

echo "===== assert EvidenceStore summaries ====="
python3 - <<'PY'
import json
from pathlib import Path

def first_summary(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    items = data.get("items") or data.get("objects") or []
    assert items, data
    return items[0].get("summary") or {}

review = first_summary("/tmp/ssentinel-runtime-action-review-search.json")
pause = first_summary("/tmp/ssentinel-runtime-action-pause-search.json")

assert review["objectType"] == "runtimeActionRecommendation", review
assert review["schemaVersion"] == "runtime.action.recommendation/v1alpha1", review
assert review["runtimeActionRecommendationId"] == "rar-runtime-action-review-store-smoke", review
assert review["recommendationStatus"] == "REVIEW_RECOMMENDED", review
assert review["recommendedAction"] == "REQUIRE_REVIEW", review
assert review["riskLevel"] == "medium", review
assert review["confidence"] == "medium", review
assert review["approvalRequired"] is True, review
assert review["rolloutName"] == "demo-app", review
assert review["namespace"] == "slo-rollout", review
assert review["rolloutPhase"] == "Progressing", review
assert review["analysisStatus"] == "Running", review
assert review["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-review-store-smoke", review
assert review["readOnly"] is True, review
assert review["recommendationOnly"] is True, review
assert review["willExecute"] is False, review
assert review["doesNotModifyKubernetes"] is True, review

assert pause["objectType"] == "runtimeActionRecommendation", pause
assert pause["runtimeActionRecommendationId"] == "rar-runtime-action-failed-store-smoke", pause
assert pause["recommendationStatus"] == "ACTION_RECOMMENDED", pause
assert pause["recommendedAction"] == "PAUSE_ROLLOUT", pause
assert pause["riskLevel"] == "high", pause
assert pause["confidence"] == "high", pause
assert pause["approvalRequired"] is True, pause
assert "rollout_phase_degraded" in pause["reasons"], pause
assert "analysis_not_successful" in pause["reasons"], pause
assert pause["rolloutPhase"] == "Degraded", pause
assert pause["analysisStatus"] == "Failed", pause
assert pause["sourceRolloutRuntimeInspectId"] == "rti-runtime-action-failed-store-smoke", pause
assert pause["willExecute"] is False, pause
assert pause["doesNotModifyKubernetes"] is True, pause

print("PASS evidence-store runtime action recommendation")
PY
