package ssentinel.release

# OPA/Rego policy contract for S Sentinel.
#
# By default the policy-runtime adapter keeps OPA in preview-only mode.
# Real opa eval is only used when S_SENTINEL_POLICY_RUNTIME_EXTERNAL_COMMANDS=1
# is set. Tests use a fake opa binary so local machines do not need OPA installed.

default allow = false

decision := {
  "schemaVersion": "release.policy.evaluator/v1alpha1",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "allowed": false,
  "finalAction": "MANUAL_REVIEW",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "reason": "OPA runtime is guarded by the PolicyRuntime adapter",
  "matchedRules": ["policy_runtime_preview_only"],
  "approvalRequiredReasons": ["policy_runtime_preview_only"],
} {
  input.schemaVersion == "policy.input/v1alpha1"
}
