#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-advisor-release-intelligence-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run advisor release intelligence integration test ====="

RELEASE_CONTEXT_FILE=tests/fixtures/release-context/fail-multiple-slo.json \
ADVISOR_REPORT_TEXT_LIMIT=1000 \
./scripts/ai-release-advisor.sh tests/fixtures/release-report/minimal-report.md \
  >"$TEST_TMP/advisor.log" 2>&1

grep -E 'Release evidence bundle generated|Running release memory builder|Running release intelligence builder|Release intelligence generated|Release intelligence linked' "$TEST_TMP/advisor.log" || true

RELEASE_EVIDENCE="$(grep 'Release evidence bundle generated:' "$TEST_TMP/advisor.log" | tail -1 | awk '{print $NF}')"

if [ -z "$RELEASE_EVIDENCE" ] || [ ! -f "$RELEASE_EVIDENCE" ]; then
  echo "FAILED: release evidence not generated or not found: ${RELEASE_EVIDENCE:-empty}" >&2
  exit 1
fi

python3 - "$RELEASE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
evidence = json.loads(evidence_path.read_text(encoding="utf-8"))

artifacts = evidence.get("artifacts", {})
ref = evidence.get("releaseIntelligenceRef") or {}

intelligence_json = artifacts.get("releaseIntelligence")
intelligence_md = artifacts.get("releaseIntelligenceReport")

assert intelligence_json, artifacts
assert intelligence_md, artifacts
assert ref.get("generated") is True, ref
assert ref.get("readOnlyAnalysis") is True, ref

intelligence_path = Path(intelligence_json)
intelligence_md_path = Path(intelligence_md)

assert intelligence_path.exists(), intelligence_path
assert intelligence_md_path.exists(), intelligence_md_path

intel = json.loads(intelligence_path.read_text(encoding="utf-8"))
md = intelligence_md_path.read_text(encoding="utf-8")

assert intel["schemaVersion"] == "release.intelligence/v1alpha1", intel
assert intel["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", intel["release"]
assert set(intel["release"]["failedMetrics"]) == {"error-rate", "p95-latency"}, intel["release"]
assert intel["intelligence"]["recommendedNextAction"] == "STOP_PROMOTION", intel["intelligence"]
assert intel["intelligence"]["riskPattern"] in {
    "new_slo_failure_pattern",
    "similar_slo_failure_pattern",
    "repeated_slo_failure_pattern",
}, intel["intelligence"]
assert intel["guardrails"]["readOnlyAnalysis"] is True, intel["guardrails"]
assert intel["guardrails"]["doesNotModifyKubernetes"] is True, intel["guardrails"]
assert intel["guardrails"]["doesNotRollback"] is True, intel["guardrails"]

assert "Release Intelligence Summary" in md
assert "STOP_PROMOTION" in md

print("Advisor release intelligence integration test passed")
PY
