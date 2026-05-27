#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-evidence-record-runtime-action-request-links"
RELEASE_ID="20260527-030303"

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

cat > "$TEST_TMP/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-action-request-evidence",
  "generatedAt": "2026-05-27T03:03:03Z",
  "generatedBy": "test-evidence-record-runtime-action-request-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-$RELEASE_ID.json",
    "runtimeActionRecommendation": "runtime-action-recommendation-$RELEASE_ID.json",
    "runtimeActionRequest": "runtime-action-request-$RELEASE_ID.json"
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

echo "===== assert evidence record runtime action request links ====="
python3 - "$RECORD" "$RELEASE_ID" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release_id = sys.argv[2]

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}
request = record.get("runtimeActionRequest") or {}

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == release_id, record

assert links.get("runtimeActionRequest", "").endswith(f"runtime-action-request-{release_id}.json"), links
assert artifacts["runtimeActionRequest"]["exists"] is True, artifacts.get("runtimeActionRequest")

assert request["runtimeActionRequestId"] == "rarq-" + release_id, request
assert request["mode"] == "request_only", request
assert request["sourceRuntimeActionRecommendationId"] == "rar-" + release_id, request
assert request["requestedAction"] == "REQUIRE_REVIEW", request
assert request["requestStatus"] == "REVIEW_REQUIRED", request
assert request["lifecycleStage"] == "WAITING_REVIEW", request
assert request["requestedBy"] == "test-runtime-controller", request
assert request["riskLevel"] == "medium", request
assert request["confidence"] == "medium", request
assert request["approvalRequired"] is True, request
assert request["readyToExecute"] is False, request
assert request["willExecute"] is False, request

assert request["recommendationStatus"] == "REVIEW_RECOMMENDED", request
assert request["recommendedAction"] == "REQUIRE_REVIEW", request
assert request["allowedToRequest"] is True, request
assert request["blockingReasons"] == [], request

assert request["approvalStatus"] == "NOT_APPROVED", request
assert request["approved"] is False, request
assert request["approvalDecision"] is None, request

assert request["rolloutName"] == "demo-app", request
assert request["namespace"] == "slo-rollout", request
assert request["service"] == "demo-app", request
assert request["env"] == "dev", request
assert request["rolloutPhase"] == "Progressing", request
assert request["analysisStatus"] == "Running", request

assert request["sourceRuntimeActionRecommendation"].endswith(f"runtime-action-recommendation-{release_id}.json"), request
assert request["sourceRolloutRuntimeInspect"].endswith(f"rollout-runtime-inspect-{release_id}.json"), request
assert request["sourceRolloutRuntimeInspectId"] == "rti-" + release_id, request
assert request["sourceRuntimeActionRequest"].endswith(f"runtime-action-request-{release_id}.json"), request

assert request["guardrails"]["requestOnly"] is True, request
assert request["guardrails"]["readOnly"] is True, request
assert request["guardrails"]["willExecute"] is False, request
assert request["guardrails"]["doesNotPause"] is True, request
assert request["guardrails"]["doesNotModifyKubernetes"] is True, request

assert record["coverage"]["total"] == 58, record["coverage"]

print("PASS evidence-record runtime action request links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
