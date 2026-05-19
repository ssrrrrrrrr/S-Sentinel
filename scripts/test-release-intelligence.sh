#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-release-intelligence-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run release intelligence test ====="

cat > "$TEST_TMP/release-evidence-previous.json" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "ALLOW_ADVISORY_ONLY",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "summary": {
    "rolloutPhase": "Degraded",
    "rolloutAbort": true,
    "analysisRunPhase": "Failed",
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "artifacts": {}
}
JSON

sleep 1

cat > "$TEST_TMP/release-evidence-current.json" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "ALLOW_ADVISORY_ONLY",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "summary": {
    "rolloutPhase": "Degraded",
    "rolloutAbort": true,
    "analysisRunPhase": "Failed",
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "artifacts": {}
}
JSON

RELEASE_REPORT_DIR="$TEST_TMP" \
  ./scripts/build-release-memory.sh

RELEASE_REPORT_DIR="$TEST_TMP" \
RELEASE_INTELLIGENCE_OUTPUT_DIR="$TEST_TMP" \
  ./scripts/build-release-intelligence.sh "$TEST_TMP/release-evidence-current.json"

python3 - "$TEST_TMP/release-intelligence-current.json" "$TEST_TMP/release-intelligence-current.md" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
md = Path(sys.argv[2]).read_text(encoding="utf-8")

assert data["schemaVersion"] == "release.intelligence/v1alpha1", data
assert data["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", data["release"]
assert set(data["release"]["failedMetrics"]) == {"error-rate", "p95-latency"}, data["release"]
assert data["history"]["similarFailureCount"] == 1, data["history"]
assert data["history"]["exactHistoricalMetricSetMatchCount"] == 1, data["history"]
assert data["intelligence"]["riskPattern"] == "repeated_slo_failure_pattern", data["intelligence"]
assert data["intelligence"]["repeatedRiskPattern"] is True, data["intelligence"]
assert data["intelligence"]["recommendedNextAction"] == "STOP_PROMOTION", data["intelligence"]
assert data["guardrails"]["doesNotModifyKubernetes"] is True, data["guardrails"]
assert data["guardrails"]["doesNotRollback"] is True, data["guardrails"]

assert "Release Intelligence Summary" in md
assert "repeated_slo_failure_pattern" in md
assert "STOP_PROMOTION" in md

print("Release intelligence test passed")
PY
