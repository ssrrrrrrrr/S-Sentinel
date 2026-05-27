#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MATERIALIZE_SCRIPT="scripts/run-gitops-real-pr-materialize-files.sh"
LOCAL_COMMIT_SCRIPT="scripts/run-gitops-real-pr-local-commit.sh"
PUSH_BRANCH_SCRIPT="scripts/run-gitops-real-pr-push-branch.sh"
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

grep -q '"willExecute": True' "$MATERIALIZE_SCRIPT"
grep -q 'didMaterializeFiles' "$MATERIALIZE_SCRIPT"
grep -q 'doesNotCommit' "$MATERIALIZE_SCRIPT"
grep -q 'doesNotPush' "$MATERIALIZE_SCRIPT"

grep -q '"willExecute": True' "$LOCAL_COMMIT_SCRIPT"
grep -q 'didCreateLocalCommit' "$LOCAL_COMMIT_SCRIPT"
grep -q 'doesNotPush' "$LOCAL_COMMIT_SCRIPT"

grep -q 'S_SENTINEL_ALLOW_GITHUB_WRITE' "$PUSH_BRANCH_SCRIPT"
grep -q 'S_SENTINEL_GITHUB_WRITE_OPERATION' "$PUSH_BRANCH_SCRIPT"
grep -q 'push-branch' "$PUSH_BRANCH_SCRIPT"
grep -q '"writeGate": write_gate' "$PUSH_BRANCH_SCRIPT"
grep -q '"requiredOperation": "push-branch"' "$PUSH_BRANCH_SCRIPT"
grep -q '"willExecute": True' "$PUSH_BRANCH_SCRIPT"
grep -q 'didPushBranch' "$PUSH_BRANCH_SCRIPT"
grep -q '"push", "-u", "origin"' "$PUSH_BRANCH_SCRIPT"
grep -q 'doesNotCreatePullRequest' "$PUSH_BRANCH_SCRIPT"

grep -q 'S_SENTINEL_GITHUB_WRITE_OPERATION' "$CREATE_SCRIPT"
grep -q 'create-pr' "$CREATE_SCRIPT"
grep -q '"writeGate": write_gate' "$CREATE_SCRIPT"
grep -q '"requiredOperation": "create-pr"' "$CREATE_SCRIPT"
grep -q '"gh", "pr", "create"' "$CREATE_SCRIPT"
grep -q '"willExecute": True' "$CREATE_SCRIPT"
grep -q 'didCreatePullRequest' "$CREATE_SCRIPT"
grep -q 'target_owner' "$CREATE_SCRIPT"
grep -q 'target_base_branch' "$CREATE_SCRIPT"

if grep -q 'ssrrrrrrrr:' "$CREATE_SCRIPT"; then
  echo "ERROR: hardcoded PR head owner found in $CREATE_SCRIPT" >&2
  exit 1
fi

if grep -Eq '"--base"[[:space:]]*,[[:space:]]*"main"' "$CREATE_SCRIPT"; then
  echo "ERROR: hardcoded PR base branch found in $CREATE_SCRIPT" >&2
  exit 1
fi

grep -q 'S_SENTINEL_GITHUB_WRITE_OPERATION' "$CLEANUP_SCRIPT"
grep -q 'cleanup-pr' "$CLEANUP_SCRIPT"
grep -q '"writeGate": write_gate' "$CLEANUP_SCRIPT"
grep -q '"requiredOperation": "cleanup-pr"' "$CLEANUP_SCRIPT"
grep -q '"gh", "pr", "close"' "$CLEANUP_SCRIPT"
grep -q '"push", "origin", "--delete"' "$CLEANUP_SCRIPT"
grep -q '"willExecute": True' "$CLEANUP_SCRIPT"
grep -q 'didClosePullRequest' "$CLEANUP_SCRIPT"
grep -q 'didDeleteRemoteBranch' "$CLEANUP_SCRIPT"

echo "===== default write gate check ====="
bash scripts/test-gitops-real-pr-controlled-write-guardrails.sh

echo "PASS gitops real-pr safety contract"
