#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BASE_DIR"

TEST_TMP="${1:-/tmp/slo-advisor-action-plan-test}"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP/action-plan" "$TEST_TMP/failure"

echo
echo "===== run advisor action plan integration test ====="

RELEASE_CONTEXT_FILE=tests/fixtures/release-context/fail-multiple-slo.json \
ACTION_PLAN_OUTPUT_DIR="$TEST_TMP/action-plan" \
FAILURE_EVIDENCE_OUTPUT_DIR="$TEST_TMP/failure" \
ADVISOR_REPORT_TEXT_LIMIT=1000 \
./scripts/ai-release-advisor.sh tests/fixtures/release-report/minimal-report.md \
  >"$TEST_TMP/advisor.log" 2>&1

grep -E 'Release evidence bundle generated|Running action plan builder|Linking action plan|Action plan linked' "$TEST_TMP/advisor.log" || true

RELEASE_EVIDENCE="$(grep 'Release evidence bundle generated:' "$TEST_TMP/advisor.log" | tail -1 | awk '{print $NF}')"
ACTION_PLAN_JSON="$TEST_TMP/action-plan/action-plan-latest.json"
ACTION_PLAN_MD="$TEST_TMP/action-plan/action-plan-latest.md"

if [ -z "$RELEASE_EVIDENCE" ] || [ ! -f "$RELEASE_EVIDENCE" ]; then
  echo "FAILED: release evidence not generated or not found: ${RELEASE_EVIDENCE:-empty}" >&2
  exit 1
fi

if [ ! -f "$ACTION_PLAN_JSON" ]; then
  echo "FAILED: action plan json not generated: $ACTION_PLAN_JSON" >&2
  exit 1
fi

if [ ! -f "$ACTION_PLAN_MD" ]; then
  echo "FAILED: action plan markdown not generated: $ACTION_PLAN_MD" >&2
  exit 1
fi

python3 - "$RELEASE_EVIDENCE" "$ACTION_PLAN_JSON" "$ACTION_PLAN_MD" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
action_json_path = Path(sys.argv[2])
action_md_path = Path(sys.argv[3])

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
plan = json.loads(action_json_path.read_text(encoding="utf-8"))
plan_md = action_md_path.read_text(encoding="utf-8")

artifacts = evidence.get("artifacts", {})
action_ref = evidence.get("actionPlanRef", {})

assert artifacts.get("actionPlan"), artifacts
assert artifacts.get("actionPlanReport"), artifacts
assert Path(artifacts["actionPlan"]).exists(), artifacts
assert Path(artifacts["actionPlanReport"]).exists(), artifacts

assert action_ref.get("generated") is True, action_ref
assert action_ref.get("executionMode") == "dry_run", action_ref
assert action_ref.get("willExecute") is False, action_ref

assert plan["schemaVersion"] == "release.action-plan/v1alpha1", plan
assert plan["releaseResult"] == "FAIL_BY_MULTIPLE_SLO", plan
assert plan["finalAction"] == "STOP_PROMOTION", plan
assert plan["executionMode"] == "dry_run", plan
assert plan["willExecute"] is False, plan
assert plan["requiresHumanApproval"] is True, plan
assert plan["actionPlan"]["blocked"] is False, plan["actionPlan"]
assert len(plan["actionPlan"]["candidateCommands"]) == 3, plan["actionPlan"]
assert any(cmd["name"] == "candidate_abort_rollout" for cmd in plan["actionPlan"]["candidateCommands"]), plan["actionPlan"]

assert plan["guardrails"]["dryRunOnly"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotModifyKubernetes"] is True, plan["guardrails"]
assert plan["guardrails"]["doesNotCommitOrPush"] is True, plan["guardrails"]

assert "Dry-run 动作计划" in plan_md
assert "是否真实执行：`false`" in plan_md

print("Advisor action plan integration test passed")
PY
