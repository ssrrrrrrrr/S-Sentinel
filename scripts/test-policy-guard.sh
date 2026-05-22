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
    {
        "name": "signed-gate-requires-approval",
        "releaseResult": "PASS",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": True,
        "strategyRequiresHumanApproval": False,
        "signedGateDecision": "REQUIRE_HUMAN_APPROVAL",
        "signedGateAllowed": False,
        "expectedDecision": "REQUIRE_HUMAN_APPROVAL",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": True,
        "expectedRule": "signed_release_gate_requires_human_approval",
    },
    {
        "name": "signed-gate-verification-requires-approval",
        "releaseResult": "PASS",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": True,
        "strategyRequiresHumanApproval": False,
        "signedGateDecision": "ALLOW",
        "signedGateAllowed": True,
        "signedGateVerification": {
            "schemaVersion": "signed.release.gate.verification/v1alpha1",
            "mode": "external_command",
            "tool": "cosign",
            "toolBinary": "/tmp/ssentinel-missing-cosign",
            "toolAvailable": False,
            "results": {
                "signatureVerified": False,
                "sbomPresent": False,
                "provenancePresent": False,
                "slsaLevelPresent": False,
                "externalVerificationRequested": True,
                "externalVerificationAllowed": False,
                "externalVerificationExecuted": False,
                "externalVerificationSucceeded": None,
                "externalVerificationSkippedReason": "external_command_not_enabled",
            },
            "guardrails": {
                "readOnly": True,
                "willExecute": False,
                "canRunExternalVerification": False,
                "doesNotRunExternalCommands": True,
                "doesNotVerifyExternalServices": True,
            },
        },
        "expectedDecision": "REQUIRE_HUMAN_APPROVAL",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": True,
        "expectedRule": "signed_release_gate_verification_requires_human_approval",
    },
    {
        "name": "signed-gate-external-verification-failed-deny",
        "releaseResult": "PASS",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": True,
        "strategyRequiresHumanApproval": False,
        "signedGateDecision": "ALLOW",
        "signedGateAllowed": True,
        "signedGateVerification": {
            "schemaVersion": "signed.release.gate.verification/v1alpha1",
            "mode": "external_command",
            "tool": "cosign",
            "toolBinary": "/tmp/fake-cosign-fail",
            "toolAvailable": True,
            "results": {
                "signatureVerified": True,
                "sbomPresent": True,
                "provenancePresent": True,
                "slsaLevelPresent": True,
                "externalVerificationRequested": True,
                "externalVerificationAllowed": True,
                "externalVerificationExecuted": True,
                "externalVerificationSucceeded": False,
                "externalVerificationSkippedReason": None,
            },
            "guardrails": {
                "readOnly": True,
                "willExecute": True,
                "canRunExternalVerification": True,
                "doesNotRunExternalCommands": False,
                "doesNotVerifyExternalServices": False,
            },
        },
        "expectedDecision": "DENY",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": False,
        "expectedRule": "signed_release_gate_verification_failed",
    },
    {
        "name": "signed-gate-block-deny",
        "releaseResult": "PASS",
        "action": "PROMOTE",
        "actionAllowed": True,
        "actionRequiresApproval": False,
        "rollbackAllowed": False,
        "autoPromotionEnabled": True,
        "strategyRequiresHumanApproval": False,
        "signedGateDecision": "BLOCK",
        "signedGateAllowed": False,
        "expectedDecision": "DENY",
        "expectedFinalAction": "PROMOTE",
        "expectedAllowed": False,
        "expectedRule": "signed_release_gate_blocked",
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

    if case.get("signedGateDecision"):
        ai_decision["signedReleaseGate"] = {
            "schemaVersion": "signed.release.gate/v1alpha1",
            "signedReleaseGateId": f"srg-{case['name']}",
            "mode": "read_only_signed_release_gate",
            "decision": {
                "decision": case["signedGateDecision"],
                "allowed": case["signedGateAllowed"],
                "requiresHumanApproval": case["signedGateDecision"] == "REQUIRE_HUMAN_APPROVAL",
                "blockingReasons": ["signed gate blocked release"] if case["signedGateDecision"] == "BLOCK" else [],
                "warningReasons": ["signed gate requires human approval"] if case["signedGateDecision"] == "REQUIRE_HUMAN_APPROVAL" else [],
            },
            "risk": {
                "riskLevel": "critical" if case["signedGateDecision"] == "BLOCK" else "high",
                "riskScore": 90 if case["signedGateDecision"] == "BLOCK" else 50,
            },
            "guardrails": {
                "readOnly": True,
                "willExecute": False,
            },
        }

        if case.get("signedGateVerification"):
            ai_decision["signedReleaseGate"]["verification"] = case["signedGateVerification"]

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

    if case.get("signedGateVerification"):
        assert data["signedReleaseGate"]["verification"]["mode"] == "external_command", data

        if case["name"] == "signed-gate-verification-requires-approval":
            assert data["signedReleaseGate"]["verification"]["signatureVerified"] is False, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationRequested"] is True, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationAllowed"] is False, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationExecuted"] is False, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationSucceeded"] is None, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationSkippedReason"] == "external_command_not_enabled", data
            assert "signed_release_gate_signature_not_verified" in data["approvalRequiredReasons"], data
            assert "signed_release_gate_external_verification_disabled" in data["approvalRequiredReasons"], data

        if case["name"] == "signed-gate-external-verification-failed-deny":
            assert data["signedReleaseGate"]["verification"]["signatureVerified"] is True, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationRequested"] is True, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationAllowed"] is True, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationExecuted"] is True, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationSucceeded"] is False, data
            assert data["signedReleaseGate"]["verification"]["externalVerificationSkippedReason"] is None, data
            assert "signed_release_gate_external_verification_failed" in data["deniedReasons"], data

    print(f"PASS: {case['name']} => {case['expectedDecision']}/{case['expectedFinalAction']}")

print("PASS: policy guard strategy-aware regression tests passed")
PY
