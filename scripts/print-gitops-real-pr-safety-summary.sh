#!/usr/bin/env bash
set -euo pipefail

cat <<'TEXT'
Real GitOps PR Safety Summary

Read-only / local-only steps:
- plan: no external write
- workspace: isolated local repo only
- materialization plan: no external write
- materialize files: local workspace write only, no commit/push/PR/Kubernetes
- local commit: local commit only, no push/PR/Kubernetes
- push preflight: no external write
- PR create preflight: no external write

Real GitHub write steps:
- push-branch:
  requires S_SENTINEL_ALLOW_GITHUB_WRITE=true
  requires S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch
- create-pr:
  requires S_SENTINEL_ALLOW_GITHUB_WRITE=true
  requires S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr
- cleanup-pr:
  requires S_SENTINEL_ALLOW_GITHUB_WRITE=true
  requires S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr

Forbidden in Real GitOps PR flow:
- no kubectl
- no helm upgrade / rollback / install
- no argo rollouts promote / abort / restart
- no PR merge
- no direct Kubernetes runtime mutation
TEXT
