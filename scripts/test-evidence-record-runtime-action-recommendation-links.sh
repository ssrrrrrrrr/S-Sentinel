#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-evidence-record-runtime-action-recommendation-links"
RELEASE_ID="20260527-020202"

rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo "===== build rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="$RELEASE_ID" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TEST_TMP"

echo "===== build runtime action recommendation ====="
RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR="$TEST_TMP" \
bash scripts/build-runtime-action-recommendation.sh "$TEST_TMP/rollout-runtime-inspect-$RELEASE_ID.json"

cat > "$TEST_TMP/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-action-recommendation-evidence",
  "generatedAt": "2026-05-27T02:02:02Z",
  "generatedBy": "test-evidence-record-runtime-action-recommendation-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-$RELEASE_ID.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-$RELEASE_ID.json"
  },
  "safety": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

echo "===== build evidence record ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  scripts/build-evidence-record.sh "$TEST_TMP/release-evidence-$RELEASE_ID.json"

RECORD="$TEST_TMP/evidence-record-$RELEASE_ID.json"

echo "===== assert evidence record runtime action recommendation links ====="
python3 - "$RECORD" "$RELEASE_ID" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release_id = sys.argv[2]

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}
runtime = record.get("runtimeActionRecommendation") or {}

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == release_id, record

assert links.get("runtimeActionRecommendation", "").endswith(f"runtime-action-recommendation-{release_id}.json"), links
assert artifacts["runtimeActionRecommendation"]["exists"] is True, artifacts.get("runtimeActionRecommendation")

assert runtime["runtimeActionRecommendationId"] == "rar-" + release_id, runtime
assert runtime["mode"] == "recommendation_only", runtime
assert runtime["recommendationStatus"] == "REVIEW_RECOMMENDED", runtime
assert runtime["recommendedAction"] == "REQUIRE_REVIEW", runtime
assert runtime["riskLevel"] == "medium", runtime
assert runtime["confidence"] == "medium", runtime
assert runtime["approvalRequired"] is True, runtime
assert "rollout_not_terminal_or_insufficient_confidence" in runtime["reasons"], runtime

assert runtime["rolloutName"] == "demo-app", runtime
assert runtime["namespace"] == "slo-rollout", runtime
assert runtime["service"] == "demo-app", runtime
assert runtime["env"] == "dev", runtime
assert runtime["rolloutPhase"] == "Progressing", runtime
assert runtime["analysisStatus"] == "Running", runtime

assert runtime["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, runtime
assert runtime["sourceRuntimeActionRecommendation"].endswith(f"runtime-action-recommendation-{release_id}.json"), runtime

assert runtime["guardrails"]["readOnly"] is True, runtime
assert runtime["guardrails"]["recommendationOnly"] is True, runtime
assert runtime["guardrails"]["willExecute"] is False, runtime
assert runtime["guardrails"]["doesNotModifyKubernetes"] is True, runtime

print("PASS evidence-record runtime action recommendation links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
