#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-advisor-release-memory-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run advisor release memory integration test ====="

RELEASE_CONTEXT_FILE=tests/fixtures/release-context/fail-multiple-slo.json \
ADVISOR_REPORT_TEXT_LIMIT=1000 \
./scripts/ai-release-advisor.sh tests/fixtures/release-report/minimal-report.md \
  >"$TEST_TMP/advisor.log" 2>&1

grep -E 'Release evidence bundle generated|Running release memory builder|Release memory generated' "$TEST_TMP/advisor.log" || true

RELEASE_EVIDENCE="$(grep 'Release evidence bundle generated:' "$TEST_TMP/advisor.log" | tail -1 | awk '{print $NF}')"
MEMORY_FILE="docs/release-reports/release-memory.jsonl"
MEMORY_SUMMARY="docs/release-reports/release-memory-latest.json"

if [ -z "$RELEASE_EVIDENCE" ] || [ ! -f "$RELEASE_EVIDENCE" ]; then
  echo "FAILED: release evidence not generated or not found: ${RELEASE_EVIDENCE:-empty}" >&2
  exit 1
fi

if [ ! -f "$MEMORY_FILE" ]; then
  echo "FAILED: release memory jsonl not generated: $MEMORY_FILE" >&2
  exit 1
fi

if [ ! -f "$MEMORY_SUMMARY" ]; then
  echo "FAILED: release memory latest summary not generated: $MEMORY_SUMMARY" >&2
  exit 1
fi

python3 - "$RELEASE_EVIDENCE" "$MEMORY_FILE" "$MEMORY_SUMMARY" <<'PY'
import json
import sys
from pathlib import Path

release_evidence = Path(sys.argv[1])
memory_file = Path(sys.argv[2])
memory_summary = Path(sys.argv[3])

records = []
for line in memory_file.read_text(encoding="utf-8").splitlines():
    if line.strip():
        records.append(json.loads(line))

summary = json.loads(memory_summary.read_text(encoding="utf-8"))

matched = [r for r in records if r.get("sourceReleaseEvidence") == str(release_evidence)]

assert matched, f"release evidence not found in memory: {release_evidence}"
record = matched[-1]

assert record["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", record
assert record["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", record
assert record["finalAction"] == "STOP_PROMOTION", record
assert record["requiresHumanApproval"] is True, record
assert set(record["failedMetrics"]) == {"error-rate", "p95-latency"}, record
assert record["actionPlan"]["generated"] is True, record["actionPlan"]
assert record["actionPlan"]["executionMode"] == "dry_run", record["actionPlan"]
assert record["actionPlan"]["willExecute"] is False, record["actionPlan"]

assert summary["recordCount"] >= 1, summary
assert summary["failureCount"] >= 1, summary

print("Advisor release memory integration test passed")
PY
