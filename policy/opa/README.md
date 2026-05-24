# S Sentinel OPA Runtime Contract Preview

This directory is the preview-only OPA policy bundle location for Stage45.

Current status:

- Runtime name: `opa`
- Policy language: Rego
- Bundle path: `policy/opa`
- Policy file: `policy/opa/release_policy.rego`
- Entrypoint: `data.ssentinel.release.decision`
- Input contract: `policy.input/v1alpha1`
- Output contract: `release.policy.evaluator/v1alpha1`

By default, the PolicyRuntime adapter still returns a preview-only result and does not execute `opa eval`. Guarded execution is available only when `S_SENTINEL_POLICY_RUNTIME_EXTERNAL_COMMANDS=1` is set. Tests use a fake `opa` binary to validate the adapter boundary without requiring OPA to be installed on the host.
