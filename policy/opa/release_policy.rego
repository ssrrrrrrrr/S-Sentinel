package ssentinel.release

# Preview-only OPA/Rego policy contract for S Sentinel.
#
# This file documents the future OPA entrypoint and output shape.
# Stage45.2 does not execute opa eval. The policy-runtime-adapter.py
# still returns a preview-only result for the opa runtime.

default allow = false

decision := {
  "schemaVersion": "release.policy.evaluator/v1alpha1",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "allowed": false,
  "finalAction": "MANUAL_REVIEW",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "reason": "OPA runtime is registered as preview-only",
  "matchedRules": ["policy_runtime_preview_only"],
  "approvalRequiredReasons": ["policy_runtime_preview_only"],
} {
  input.schemaVersion == "policy.input/v1alpha1"
}
