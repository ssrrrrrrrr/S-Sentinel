#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - "$TMP_DIR" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

tmp_dir = Path(sys.argv[1])
repo = Path.cwd()

cases = [
    {
        "name": "pass-noop",
        "releaseResult": "PASS",
        "action": "NOOP",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": False,
        "expectedDecision": "ALLOW_ADVISORY_ONLY",
        "expectedFinalAction": "NOOP",
        "expectedAllowed": True,
        "expectedRule": "pass_release_no_action",
    },
    {
        "name": "request-count-retry",
        "releaseResult": "FAIL_BY_REQUEST_COUNT",
        "action": "RETRY_WITH_MORE_TRAFFIC",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": False,
        "expectedDecision": "ALLOW_ADVISORY_ONLY",
        "expectedFinalAction": "NOOP",
        "expectedAllowed": True,
        "expectedRule": "insufficient_traffic_retry_observation_allowed_by_strategy",
    },
    {
        "name": "multiple-slo-stop",
        "releaseResult": "FAIL_BY_MULTIPLE_SLO",
        "action": "STOP_PROMOTION",
        "actionAllowed": True,
        "actionRequiresApproval": True,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": True,
        "expectedDecision": "REQUIRE_HUMAN_APPROVAL",
        "expectedFinalAction": "STOP_PROMOTION",
        "expectedAllowed": True,
        "expectedRule": "slo_failure_stop_promotion_allowed_by_strategy",
    },
    {
        "name": "multiple-slo-promote-deny",
        "releaseResult": "FAIL_BY_MULTIPLE_SLO",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": True,
        "expectedDecision": "DENY",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": False,
        "expectedRule": "promote_denied_unless_release_passed_and_strategy_allows",
    },
    {
        "name": "multiple-slo-rollback-deny",
        "releaseResult": "FAIL_BY_MULTIPLE_SLO",
        "action": "ROLLBACK",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": True,
        "expectedDecision": "DENY",
        "expectedFinalAction": "ROLLBACK",
        "expectedAllowed": False,
        "expectedRule": "rollback_denied_by_strategy",
    },
    {
        "name": "pass-promote-auto-allowed",
        "releaseResult": "PASS",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": True,
        "strategyRequiresHumanApproval": False,
        "expectedDecision": "ALLOW_ADVISORY_ONLY",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": True,
        "expectedRule": "pass_auto_promote_allowed_by_strategy",
    },
    {
        "name": "unknown-manual-review",
        "releaseResult": "UNKNOWN",
        "action": "MANUAL_REVIEW",
        "actionAllowed": True,
        "actionRequiresApproval": True,
        "rollbackAllowed": False,
        "autoPromotionEnabled": False,
        "strategyRequiresHumanApproval": True,
        "expectedDecision": "REQUIRE_HUMAN_APPROVAL",
        "expectedFinalAction": "INVESTIGATE",
        "expectedAllowed": True,
        "expectedRule": "fallback_manual_review_required",
    },
]

for case in cases:
    case_dir = tmp_dir / case["name"]
    case_dir.mkdir(parents=True, exist_ok=True)

    ai_path = case_dir / f"ai-decision-{case['name']}.json"
    policy_path = case_dir / f"policy-decision-{case['name']}.json"
    policy_config_path = case_dir / "release-policy.yaml"

    policy_config_path.write_text("""schemaVersion: release.policy/v1alpha1
executionMode: advisory_only
autoExecute: false
blockedActions:
  - DELETE_RESOURCE
  - PATCH_RESOURCE
  - APPLY_MANIFEST
dangerousActions:
  - DELETE_RESOURCE
  - PATCH_RESOURCE
  - APPLY_MANIFEST
""", encoding="utf-8")

    ai_decision = {
        "schemaVersion": "ai.release.advisor/v1alpha1",
        "generatedBy": "test-policy-guard.sh",
        "model": "deterministic-test",
        "releaseResult": case["releaseResult"],
        "decisionSource": "deterministic_rule",
        "confidence": "high",
        "executionMode": "advisory_only",
        "summary": "test",
        "conclusion": "test",
        "failedMetrics": [],
        "riskLevel": "low" if case["releaseResult"] == "PASS" else "critical",
        "riskScore": 0 if case["releaseResult"] == "PASS" else 100,
        "riskReasons": [],
        "decision": "test",
        "recommendedAction": case["action"],
        "requiresHumanApproval": case["actionRequiresApproval"],
        "safeToRetry": False,
        "service": "demo-app",
        "env": "dev",
        "sloId": "demo-app-canary-slo",
        "strategyId": "demo-app-canary-strategy",
        "strategyType": "canary",
        "strategyFailurePolicy": {
            "onSLOFailure": "stop_promotion",
            "onAnalysisError": "require_manual_review",
            "onInsufficientTraffic": "retry_with_more_traffic",
            "rollbackAllowed": case["rollbackAllowed"],
        },
        "strategyPromotionPolicy": {
            "autoPromotionEnabled": case["autoPromotionEnabled"],
            "requiresHumanApproval": case["strategyRequiresHumanApproval"],
            "finalPromotionMode": "manual",
        },
        "policyHints": [],
        "agentAction": {
            "type": case["action"],
            "allowed": case["actionAllowed"],
            "requiresApproval": case["actionRequiresApproval"],
            "reason": "test",
        },
        "guardrails": {
            "autoExecute": False,
            "executionMode": "advisory_only",
            "allowedActions": [
                "NOOP",
                "OBSERVE",
                "RETRY_WITH_MORE_TRAFFIC",
                "STOP_PROMOTION",
                "INVESTIGATE",
                "MANUAL_REVIEW",
                "ROLLBACK",
                "PROMOTE",
            ],
            "blockedActions": [
                "DELETE_RESOURCE",
                "PATCH_RESOURCE",
                "APPLY_MANIFEST",
            ],
        },
        "evidence": {
            "service": "demo-app",
            "env": "dev",
            "sloId": "demo-app-canary-slo",
            "strategyId": "demo-app-canary-strategy",
            "strategyType": "canary",
        },
        "nextSteps": [],
        "rollout": {},
        "analysisRun": {},
        "sources": {},
    }

    ai_path.write_text(json.dumps(ai_decision, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    env = os.environ.copy()
    env["RELEASE_REPORT_DIR"] = str(case_dir)
    env["RELEASE_POLICY_FILE"] = str(policy_config_path)
    env["RELEASE_CONTRACT_VALIDATION_MODE"] = "warn"

    subprocess.run(
        [str(repo / "scripts" / "evaluate-agent-decision.sh"), str(ai_path)],
        cwd=repo,
        env=env,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    data = json.loads(policy_path.read_text(encoding="utf-8"))

    assert data["policyDecision"] == case["expectedDecision"], data
    assert data["finalAction"] == case["expectedFinalAction"], data
    assert data["allowed"] is case["expectedAllowed"], data
    assert data["requestedAction"] == case["action"], data
    assert case["expectedRule"] in data["matchedRules"], data
    assert data["strategyId"] == "demo-app-canary-strategy", data
    assert data["strategyPolicy"]["strategyId"] == "demo-app-canary-strategy", data
    assert data["safety"]["readOnly"] is True, data
    assert data["safety"]["willExecute"] is False, data

    print(f"PASS: {case['name']} => {case['expectedDecision']}/{case['expectedFinalAction']}")

print("PASS: policy guard strategy-aware regression tests passed")
PY
