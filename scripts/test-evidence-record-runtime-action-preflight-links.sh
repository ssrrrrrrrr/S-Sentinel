#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-evidence-record-runtime-action-preflight-links"
RELEASE_ID="20260527-040404"

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

echo "===== build runtime action request ====="
RUNTIME_ACTION_REQUEST_OUTPUT_DIR="$TEST_TMP" \
REQUESTED_BY="test-runtime-controller" \
bash scripts/build-runtime-action-request.sh "$TEST_TMP/runtime-action-recommendation-$RELEASE_ID.json"

echo "===== build runtime action preflight ====="
RUNTIME_ACTION_PREFLIGHT_OUTPUT_DIR="$TEST_TMP" \
bash scripts/build-runtime-action-preflight.sh "$TEST_TMP/runtime-action-request-$RELEASE_ID.json"

cat > "$TEST_TMP/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-action-preflight-evidence",
  "generatedAt": "2026-05-27T04:04:04Z",
  "generatedBy": "test-evidence-record-runtime-action-preflight-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-$RELEASE_ID.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-$RELEASE_ID.json",
    "runtimeActionRequest": "runtime-action-request-$RELEASE_ID.json",
    "runtimeActionPreflight": "runtime-action-preflight-$RELEASE_ID.json"
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

echo "===== assert evidence record runtime action preflight links ====="
python3 - "$RECORD" "$RELEASE_ID" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release_id = sys.argv[2]

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}
preflight = record.get("runtimeActionPreflight") or {}

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == release_id, record

assert links.get("runtimeActionPreflight", "").endswith(f"runtime-action-preflight-{release_id}.json"), links
assert artifacts["runtimeActionPreflight"]["exists"] is True, artifacts.get("runtimeActionPreflight")

assert preflight["runtimeActionPreflightId"] == "rap-" + release_id, preflight
assert preflight["mode"] == "read_only_runtime_action_preflight", preflight
assert preflight["sourceRuntimeActionRequestId"] == "rarq-" + release_id, preflight
assert preflight["requestedAction"] == "REQUIRE_REVIEW", preflight
assert preflight["requestStatus"] == "REVIEW_REQUIRED", preflight
assert preflight["lifecycleStage"] == "WAITING_REVIEW", preflight
assert preflight["riskLevel"] == "medium", preflight
assert preflight["confidence"] == "medium", preflight
assert preflight["approvalRequired"] is True, preflight
assert preflight["approved"] is False, preflight
assert preflight["allowedToRequest"] is True, preflight

assert preflight["preflightStatus"] == "WAITING_REVIEW", preflight
assert preflight["eligibilityStatus"] == "NEEDS_REVIEW", preflight
assert preflight["blockingReasons"] == [], preflight
assert "human_review_required" in preflight["approvalReasons"], preflight
assert preflight["warningReasons"] == [], preflight
assert preflight["eligibleForExecution"] is False, preflight
assert preflight["readyToExecute"] is False, preflight
assert preflight["willExecute"] is False, preflight

assert preflight["rolloutName"] == "demo-app", preflight
assert preflight["namespace"] == "slo-rollout", preflight
assert preflight["service"] == "demo-app", preflight
assert preflight["env"] == "dev", preflight
assert preflight["rolloutPhase"] == "Progressing", preflight
assert preflight["analysisStatus"] == "Running", preflight

assert preflight["sourceRuntimeActionRequest"].endswith(f"runtime-action-request-{release_id}.json"), preflight
assert preflight["sourceRuntimeActionRecommendation"].endswith(f"runtime-action-recommendation-{release_id}.json"), preflight
assert preflight["sourceRuntimeActionRecommendationId"] == "rar-" + release_id, preflight
assert preflight["sourceRolloutRuntimeInspect"].endswith(f"rollout-runtime-inspect-{release_id}.json"), preflight
assert preflight["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, preflight
assert preflight["sourceRuntimeActionPreflight"].endswith(f"runtime-action-preflight-{release_id}.json"), preflight

assert preflight["guardrails"]["preflightOnly"] is True, preflight
assert preflight["guardrails"]["readOnly"] is True, preflight
assert preflight["guardrails"]["willExecute"] is False, preflight
assert preflight["guardrails"]["doesNotPause"] is True, preflight
assert preflight["guardrails"]["doesNotModifyKubernetes"] is True, preflight

assert record["coverage"]["total"] == 58, record["coverage"]

print("PASS evidence-record runtime action preflight links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
