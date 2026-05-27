#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-runtime-action-recommendation"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "===== build source rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-action-review-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

echo "===== build review recommendation ====="
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-review-smoke.json"

echo "===== create failed runtime inspect fixture ====="
python3 - <<'PY'
import json
from pathlib import Path

src = Path(".tmp/test-runtime-action-recommendation/rollout-runtime-inspect-runtime-action-review-smoke.json")
dst = Path(".tmp/test-runtime-action-recommendation/rollout-runtime-inspect-runtime-action-failed-smoke.json")
data = json.loads(src.read_text(encoding="utf-8"))

data["rolloutRuntimeInspectId"] = "rti-runtime-action-failed-smoke"
data["release"]["releaseId"] = "runtime-action-failed-smoke"
data["rollout"]["phase"] = "Degraded"
data["rollout"]["degraded"] = True
data["rollout"]["readyReplicas"] = 1
data["analysis"]["status"] = "Failed"
data["analysis"]["failed"] = 1
data["pods"]["readyPodCount"] = 1

dst.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

echo "===== build pause recommendation ====="
bash scripts/build-runtime-action-recommendation.sh "$TMP_DIR/rollout-runtime-inspect-runtime-action-failed-smoke.json"

echo "===== assert recommendations ====="
python3 - <<'PY'
import json
from pathlib import Path

review = json.loads(Path(".tmp/test-runtime-action-recommendation/runtime-action-recommendation-runtime-action-review-smoke.json").read_text())
failed = json.loads(Path(".tmp/test-runtime-action-recommendation/runtime-action-recommendation-runtime-action-failed-smoke.json").read_text())

assert review["schemaVersion"] == "runtime.action.recommendation/v1alpha1", review
assert review["runtimeActionRecommendationId"] == "rar-runtime-action-review-smoke", review
assert review["mode"] == "recommendation_only", review
assert review["recommendation"]["recommendedAction"] == "REQUIRE_REVIEW", review
assert review["recommendation"]["recommendationStatus"] == "REVIEW_RECOMMENDED", review
assert review["recommendation"]["riskLevel"] == "medium", review
assert review["recommendation"]["approvalRequired"] is True, review
assert review["runtimeSnapshot"]["rolloutPhase"] == "Progressing", review
assert review["runtimeSnapshot"]["analysisStatus"] == "Running", review
assert review["guardrails"]["readOnly"] is True, review
assert review["guardrails"]["recommendationOnly"] is True, review
assert review["guardrails"]["willExecute"] is False, review
assert review["guardrails"]["doesNotModifyKubernetes"] is True, review
assert review["guardrails"]["doesNotPause"] is True, review
assert review["guardrails"]["doesNotPromote"] is True, review
assert review["guardrails"]["doesNotAbort"] is True, review
assert review["guardrails"]["doesNotRollback"] is True, review

assert failed["runtimeActionRecommendationId"] == "rar-runtime-action-failed-smoke", failed
assert failed["recommendation"]["recommendedAction"] == "PAUSE_ROLLOUT", failed
assert failed["recommendation"]["recommendationStatus"] == "ACTION_RECOMMENDED", failed
assert failed["recommendation"]["riskLevel"] == "high", failed
assert failed["recommendation"]["approvalRequired"] is True, failed
assert "rollout_phase_degraded" in failed["recommendation"]["reasons"], failed
assert "analysis_not_successful" in failed["recommendation"]["reasons"], failed
assert failed["runtimeSnapshot"]["rolloutPhase"] == "Degraded", failed
assert failed["runtimeSnapshot"]["analysisStatus"] == "Failed", failed
assert failed["guardrails"]["willExecute"] is False, failed
assert failed["guardrails"]["doesNotModifyKubernetes"] is True, failed

print("PASS runtime action recommendation")
PY
