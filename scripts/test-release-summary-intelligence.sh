#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-release-summary-intelligence-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

echo
echo "===== run release summary intelligence test ====="

cat > "$TEST_TMP/release-intelligence-current.json" <<'JSON'
{
  "schemaVersion": "release.intelligence/v1alpha1",
  "intelligence": {
    "riskPattern": "repeated_slo_failure_pattern",
    "repeatedRiskPattern": true,
    "recommendedNextAction": "STOP_PROMOTION",
    "humanSummary": "本次发布失败指标与历史失败记录完全匹配，属于重复风险模式。建议停止继续放量并人工排查。"
  },
  "history": {
    "similarFailureCount": 1,
    "exactHistoricalMetricSetMatchCount": 1,
    "similarFailures": [
      {
        "releaseId": "previous-fail",
        "appVersion": "v31-watcher-v119-multi-slo-fail",
        "releaseResult": "FAIL_BY_MULTIPLE_SLO",
        "finalAction": "STOP_PROMOTION",
        "failedMetrics": ["error-rate", "p95-latency"],
        "similarity": {
          "exactMetricSetMatch": true
        }
      }
    ]
  }
}
JSON

cat > "$TEST_TMP/release-evidence-current.json" <<JSON
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
    "failedMetrics": ["error-rate", "p95-latency"],
    "matchedPolicyRules": ["multiple_slo_failure_requires_human_approval"]
  },
  "artifacts": {
    "releaseIntelligence": "$TEST_TMP/release-intelligence-current.json",
    "releaseIntelligenceReport": "$TEST_TMP/release-intelligence-current.md"
  },
  "releaseIntelligenceRef": {
    "generated": true,
    "json": "$TEST_TMP/release-intelligence-current.json",
    "markdown": "$TEST_TMP/release-intelligence-current.md",
    "readOnlyAnalysis": true
  },
  "decisionRefs": {
    "aiDecision": {
      "agentAction": {
        "type": "STOP_PROMOTION",
        "allowed": true,
        "requiresApproval": true,
        "reason": "Release failed SLO gates and requires human investigation"
      }
    },
    "policyDecision": {
      "reason": "Multiple SLO gates failed; action is advisory only and requires human approval"
    }
  }
}
JSON

RELEASE_REPORT_DIR="$TEST_TMP" \
  ./scripts/build-release-summary.sh "$TEST_TMP/release-evidence-current.json" \
  >"$TEST_TMP/summary.log" 2>&1

cat "$TEST_TMP/summary.log"

SUMMARY_MD="$TEST_TMP/release-summary-current.md"

python3 - "$SUMMARY_MD" <<'PY'
import sys
from pathlib import Path

md = Path(sys.argv[1]).read_text(encoding="utf-8")

assert "Release Intelligence 历史智能摘要" in md
assert "repeated_slo_failure_pattern" in md
assert "Repeated Risk Pattern：`true`" in md
assert "Similar Historical Failure Count：`1`" in md
assert "Exact Historical Metric Set Match Count：`1`" in md
assert "STOP_PROMOTION" in md
assert "v31-watcher-v119-multi-slo-fail" in md
assert "## 12. 安全边界" in md

print("Release summary intelligence test passed")
PY
