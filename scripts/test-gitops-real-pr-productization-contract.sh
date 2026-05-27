#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  "scripts/print-gitops-real-pr-safety-summary.sh"
  "scripts/test-gitops-real-pr-safety-summary.sh"
  "scripts/test-gitops-real-pr-acceptance.sh"
  "scripts/test-gitops-real-pr-controlled-write-guardrails.sh"
  "scripts/test-gitops-real-pr-safety-contract.sh"
  "scripts/test-gitops-real-pr-evidence-completeness.sh"
  "scripts/test-evidence-store-gitops-real-pr.sh"
  "scripts/test-evidence-store-gitops-real-pr-local-flow.sh"
  "scripts/test-evidence-record-gitops-real-pr-links.sh"
)

for f in "${required_files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing productization contract file: $f" >&2
    exit 1
  fi
done

grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE=true" scripts/print-gitops-real-pr-safety-summary.sh
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch" scripts/print-gitops-real-pr-safety-summary.sh
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr" scripts/print-gitops-real-pr-safety-summary.sh
grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr" scripts/print-gitops-real-pr-safety-summary.sh

grep -q "test-gitops-real-pr-safety-summary.sh" scripts/test-gitops-real-pr-acceptance.sh
grep -q "test-evidence-store-gitops-real-pr-local-flow.sh" scripts/test-gitops-real-pr-acceptance.sh
grep -q "test-evidence-record-gitops-real-pr-links.sh" scripts/test-gitops-real-pr-acceptance.sh

grep -q "writeGateRequiredOperation" scripts/test-evidence-store-gitops-real-pr.sh
grep -q "gitopsRealPRBranchPush" scripts/test-evidence-store-gitops-real-pr.sh
grep -q "gitopsRealPRCreate" scripts/test-evidence-store-gitops-real-pr.sh
grep -q "gitopsRealPRCleanup" scripts/test-evidence-store-gitops-real-pr.sh

for f in \
  scripts/run-gitops-real-pr-push-branch.sh \
  scripts/run-gitops-real-pr-create.sh \
  scripts/run-gitops-real-pr-cleanup.sh
do
  grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE" "$f"
  grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION" "$f"
  grep -q '"writeGate": write_gate' "$f"

  if grep -Eq 'kubectl|helm[[:space:]]+(upgrade|rollback|install)|argo[[:space:]]+rollouts[[:space:]]+(promote|abort|restart)|gh[[:space:]]+pr[[:space:]]+merge' "$f"; then
    echo "ERROR: forbidden runtime mutation found in $f" >&2
    exit 1
  fi
done

echo "PASS gitops real-pr productization contract"
