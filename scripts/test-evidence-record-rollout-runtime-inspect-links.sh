#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-evidence-record-rollout-runtime-inspect-links"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo "===== build rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="20260527-010101" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TEST_TMP" >/tmp/ssentinel-rollout-inspect-build.log

cat /tmp/ssentinel-rollout-inspect-build.log

cat > "$TEST_TMP/release-evidence-20260527-010101.json" <<'JSON'
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "20260527-010101",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-runtime-inspect-evidence",
  "generatedAt": "2026-05-27T01:01:01Z",
  "generatedBy": "test-evidence-record-rollout-runtime-inspect-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "rolloutRuntimeInspect": "rollout-runtime-inspect-20260527-010101.json"
  },
  "safety": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

echo "===== build evidence record ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  scripts/build-evidence-record.sh "$TEST_TMP/release-evidence-20260527-010101.json" >/tmp/ssentinel-evidence-record-runtime-inspect-build.log

cat /tmp/ssentinel-evidence-record-runtime-inspect-build.log

RECORD="$TEST_TMP/evidence-record-20260527-010101.json"

echo "===== assert evidence record rollout runtime inspect links ====="
python3 - "$RECORD" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == "20260527-010101", record

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}
runtime = record.get("rolloutRuntimeInspect") or {}

assert links.get("rolloutRuntimeInspect", "").endswith("rollout-runtime-inspect-20260527-010101.json"), links
assert artifacts["rolloutRuntimeInspect"]["exists"] is True, artifacts.get("rolloutRuntimeInspect")

assert runtime["rolloutRuntimeInspectId"] == "rti-20260527-010101", runtime
assert runtime["mode"] == "fixture_rollout_runtime_inspect", runtime
assert runtime["rolloutName"] == "demo-app", runtime
assert runtime["namespace"] == "slo-rollout", runtime
assert runtime["service"] == "demo-app", runtime
assert runtime["env"] == "dev", runtime
assert runtime["rolloutPhase"] == "Progressing", runtime
assert runtime["strategy"] == "Canary", runtime
assert runtime["analysisStatus"] == "Running", runtime
assert runtime["podCount"] == 3, runtime
assert runtime["readyPodCount"] == 3, runtime
assert runtime["sourceRolloutRuntimeInspect"].endswith("rollout-runtime-inspect-20260527-010101.json"), runtime
assert runtime["guardrails"]["readOnly"] is True, runtime
assert runtime["guardrails"]["willExecute"] is False, runtime
assert runtime["guardrails"]["doesNotModifyKubernetes"] is True, runtime

print("PASS evidence-record rollout runtime inspect links")
PY

echo "===== validate evidence record schema ====="
python3 scripts/validate-release-contracts.py "$RECORD"
