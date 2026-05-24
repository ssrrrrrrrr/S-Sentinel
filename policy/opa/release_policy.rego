package ssentinel.release

import rego.v1

# OPA/Rego policy contract for S Sentinel.
#
# OPA remains preview-only by default in policy-runtime-adapter.py.
# Real opa eval is only allowed when S_SENTINEL_POLICY_RUNTIME_EXTERNAL_COMMANDS=1.

default allow := false

dangerous_actions := {
  "DELETE_RESOURCE",
  "PATCH_RESOURCE",
  "APPLY_MANIFEST",
  "EXECUTE_COMMAND",
  "SCALE_WORKLOAD",
}

slo_failure_results := {
  "FAIL_BY_ERROR_RATE",
  "FAIL_BY_P95_LATENCY",
  "FAIL_BY_MULTIPLE_SLO",
}

input_summary := object.get(input, "inputSummary", {})
release_result := object.get(input_summary, "releaseResult", "")
requested_action := object.get(input_summary, "requestedAction", "")
signed_gate_ref := object.get(input, "signedReleaseGateRef", {})
signed_gate_decision := object.get(signed_gate_ref, "decision", "")

allow if {
  decision.allowed == true
}

decision := output if {
  requested_action in dangerous_actions
  output := build_decision("DENY", false, "MANUAL_REVIEW", false, "Dangerous action is denied", ["opa_dangerous_action_denied"], ["dangerous_action_denied_by_opa_policy"], [])
} else := output if {
  signed_gate_decision == "BLOCK"
  output := build_decision("DENY", false, "MANUAL_REVIEW", false, "SignedReleaseGate blocked this release", ["opa_signed_release_gate_blocked"], ["signed_release_gate_blocked"], [])
} else := output if {
  signed_gate_decision == "REQUIRE_HUMAN_APPROVAL"
  output := build_decision("REQUIRE_HUMAN_APPROVAL", false, "MANUAL_REVIEW", true, "SignedReleaseGate requires human approval", ["opa_signed_release_gate_requires_approval"], [], ["signed_release_gate_requires_human_approval"])
} else := output if {
  release_result == "PASS"
  requested_action in {"NOOP", "OBSERVE"}
  output := build_decision("ALLOW", true, "NOOP", false, "Release passed and requested action is observational", ["opa_pass_noop_allowed"], [], [])
} else := output if {
  release_result in slo_failure_results
  requested_action == "STOP_PROMOTION"
  output := build_decision("REQUIRE_HUMAN_APPROVAL", false, "MANUAL_REVIEW", true, "SLO failure requires human approval before stopping promotion", ["opa_slo_failure_stop_promotion_requires_approval"], [], ["slo_failure_requires_human_approval"])
} else := output if {
  requested_action == "ROLLBACK"
  output := build_decision("REQUIRE_HUMAN_APPROVAL", false, "MANUAL_REVIEW", true, "Rollback requires human approval", ["opa_rollback_requires_approval"], [], ["rollback_is_high_risk_action"])
} else := output if {
  output := build_decision("DENY", false, "MANUAL_REVIEW", false, "No OPA rule matched; deny by default", ["opa_fallback_deny_unknown_or_unsafe_action"], ["fallback_deny_unknown_or_unsafe_action"], [])
}

build_decision(policy_decision, allowed_value, final_action, requires_approval, reason, matched_rules, denied_reasons, approval_reasons) := output if {
  output := {
    "schemaVersion": "release.policy.evaluator/v1alpha1",
    "policyDecisionId": sprintf("pd-opa-%s", [object.get(input, "releaseId", "unknown")]),
    "sourceDecisionFile": object.get(input, "sourceDecisionFile", null),
    "releaseId": object.get(input, "releaseId", null),
    "evidenceId": null,
    "service": object.get(input_summary, "service", null),
    "env": object.get(input_summary, "env", null),
    "sloId": object.get(input_summary, "sloId", null),
    "strategyId": object.get(input_summary, "strategyId", null),
    "policyDecision": policy_decision,
    "requestedAction": requested_action,
    "allowed": allowed_value,
    "finalAction": final_action,
    "executionMode": "advisory_only",
    "requiresHumanApproval": requires_approval,
    "reason": reason,
    "deniedReasons": denied_reasons,
    "approvalRequiredReasons": approval_reasons,
    "matchedRules": matched_rules,
    "signedReleaseGate": signed_gate_ref,
    "inputSummary": input_summary,
    "safety": {
      "readOnly": true,
      "willExecute": false,
      "doesNotModifyKubernetes": true,
      "doesNotModifyGitOps": true,
      "doesNotBuildOrPushImages": true
    },
    "policyRef": object.get(input, "policyRef", {})
  }
}
