#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CREATE_SCRIPT="scripts/run-gitops-real-pr-create.sh"
CLEANUP_SCRIPT="scripts/run-gitops-real-pr-cleanup.sh"

for script in "$CREATE_SCRIPT" "$CLEANUP_SCRIPT"; do
  if [ ! -f "$script" ]; then
    echo "ERROR: missing script: $script" >&2
    exit 1
  fi

  grep -q 'S_SENTINEL_ALLOW_GITHUB_WRITE' "$script"
  grep -q 'doesNotMergePullRequest' "$script"
  grep -q 'doesNotModifyKubernetes' "$script"

  if grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|kubectl|argo[[:space:]]+rollouts|rollout[[:space:]]+(promote|abort|restart)|helm[[:space:]]+(upgrade|rollback|install)' "$script"; then
    echo "ERROR: forbidden mutation command found in $script" >&2
    exit 1
  fi
done

grep -q '"gh", "pr", "create"' "$CREATE_SCRIPT"
grep -q 'didCreatePullRequest' "$CREATE_SCRIPT"

grep -q '"gh", "pr", "close"' "$CLEANUP_SCRIPT"
grep -q '"push", "origin", "--delete"' "$CLEANUP_SCRIPT"
grep -q 'didClosePullRequest' "$CLEANUP_SCRIPT"
grep -q 'didDeleteRemoteBranch' "$CLEANUP_SCRIPT"

echo "===== default write gate check ====="
bash scripts/test-gitops-real-pr-controlled-write-guardrails.sh

echo "PASS gitops real-pr safety contract"
