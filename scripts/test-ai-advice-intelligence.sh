#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-ai-advice-intelligence-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run AI advice intelligence test ====="

RELEASE_CONTEXT_FILE=tests/fixtures/release-context/fail-multiple-slo.json \
ADVISOR_REPORT_TEXT_LIMIT=1000 \
./scripts/ai-release-advisor.sh tests/fixtures/release-report/minimal-report.md \
  >"$TEST_TMP/advisor.log" 2>&1

grep -E 'Running release intelligence builder|Release intelligence linked|Release intelligence summary appended to AI advice' "$TEST_TMP/advisor.log" || true

RELEASE_EVIDENCE="$(grep 'Release evidence bundle generated:' "$TEST_TMP/advisor.log" | tail -1 | awk '{print $NF}')"

if [ -z "$RELEASE_EVIDENCE" ] || [ ! -f "$RELEASE_EVIDENCE" ]; then
  echo "FAILED: release evidence not generated or not found: ${RELEASE_EVIDENCE:-empty}" >&2
  exit 1
fi

python3 - "$RELEASE_EVIDENCE" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

artifacts = evidence.get("artifacts", {})
advice_path = Path(artifacts["aiAdvice"])
intelligence_path = Path(artifacts["releaseIntelligence"])

assert advice_path.exists(), advice_path
assert intelligence_path.exists(), intelligence_path
assert evidence.get("releaseIntelligenceRef", {}).get("generated") is True, evidence.get("releaseIntelligenceRef")

advice = advice_path.read_text(encoding="utf-8")
intel = json.loads(intelligence_path.read_text(encoding="utf-8"))

assert "Release Intelligence Summary" in advice
assert "Risk Pattern" in advice
assert "Repeated Risk Pattern" in advice
assert "Similar Historical Failure Count" in advice
assert "Recommended Next Action" in advice
assert "STOP_PROMOTION" in advice
assert str(intelligence_path) in advice
assert intel["release"]["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", intel["release"]

print("AI advice intelligence test passed")
PY
