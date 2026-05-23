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

Stage45.2 does not execute `opa eval`. The PolicyRuntime adapter only exposes registry metadata and a command preview. Real OPA execution should be enabled in a later stage behind explicit guardrails and regression tests.
