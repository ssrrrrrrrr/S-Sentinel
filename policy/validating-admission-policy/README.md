# S Sentinel ValidatingAdmissionPolicy Simulator Contract Preview

This directory is the preview-only ValidatingAdmissionPolicy simulator policy location for Stage45.

Current status:

- Runtime name: `validating-admission-policy-sim`
- Policy language: CEL
- Bundle path: `policy/validating-admission-policy`
- Policy file: `policy/validating-admission-policy/release-policy.yaml`
- Entrypoint: `ValidatingAdmissionPolicy/ssentinel-release-policy-preview`
- Input contract: `policy.input/v1alpha1`
- Normalized output contract: `release.policy.evaluator/v1alpha1`

Stage45.4 does not apply any Kubernetes admission resource and does not contact the Kubernetes API server. The PolicyRuntime adapter only exposes registry metadata and a command preview. A later stage can add a local simulator that maps S Sentinel policy input into an admission-style object and evaluates CEL expressions safely.
