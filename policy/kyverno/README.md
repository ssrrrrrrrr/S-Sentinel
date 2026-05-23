# S Sentinel Kyverno CLI Runtime Contract Preview

This directory is the preview-only Kyverno policy bundle location for Stage45.

Current status:

- Runtime name: `kyverno-cli`
- Policy language: Kyverno policy YAML
- Bundle path: `policy/kyverno`
- Policy file: `policy/kyverno/release-policy.yaml`
- Entrypoint: `ClusterPolicy/ssentinel-release-policy-preview`
- Input contract: `policy.input/v1alpha1`
- Normalized output contract: `release.policy.evaluator/v1alpha1`

Stage45.3 does not execute `kyverno apply`. The PolicyRuntime adapter only exposes registry metadata and a command preview. A later stage can add an input-mapping layer that converts S Sentinel policy input into a Kubernetes admission-style resource for Kyverno evaluation.
