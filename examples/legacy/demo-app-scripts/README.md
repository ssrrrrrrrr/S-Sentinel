# Legacy demo-app scripts

This directory contains early imperative release scripts used during the initial demo phase.

These scripts may generate standalone manifests and apply them directly with `kubectl`.

Current release flow is GitOps-based and uses:

- `demo-app/release-gitops.sh`
- `.github/workflows/release.yaml`
- `deploy/base/*`

Do not use scripts in this directory as the current release entry.
