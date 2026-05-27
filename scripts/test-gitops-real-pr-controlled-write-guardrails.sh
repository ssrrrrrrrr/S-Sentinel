#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-gitops-real-pr-controlled-write-guardrails"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

PUSH_PREFLIGHT="$TMP_DIR/dummy-push-preflight.json"
PR_PREFLIGHT="$TMP_DIR/dummy-pr-preflight.json"
CREATE_JSON="$TMP_DIR/dummy-pr-create.json"

echo '{}' > "$PUSH_PREFLIGHT"
echo '{}' > "$PR_PREFLIGHT"
echo '{}' > "$CREATE_JSON"

echo "===== branch push guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=false bash scripts/run-gitops-real-pr-push-branch.sh "$PUSH_PREFLIGHT" >/tmp/ssentinel-push-guardrail.log 2>&1; then
  echo "ERROR: branch push guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE=true" /tmp/ssentinel-push-guardrail.log

echo "===== branch push operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true bash scripts/run-gitops-real-pr-push-branch.sh "$PUSH_PREFLIGHT" >/tmp/ssentinel-push-operation-guardrail.log 2>&1; then
  echo "ERROR: branch push operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch" /tmp/ssentinel-push-operation-guardrail.log

echo "===== branch push wrong-operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr bash scripts/run-gitops-real-pr-push-branch.sh "$PUSH_PREFLIGHT" >/tmp/ssentinel-push-wrong-operation-guardrail.log 2>&1; then
  echo "ERROR: branch push wrong-operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch" /tmp/ssentinel-push-wrong-operation-guardrail.log

echo "===== create guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=false bash scripts/run-gitops-real-pr-create.sh "$PR_PREFLIGHT" >/tmp/ssentinel-create-guardrail.log 2>&1; then
  echo "ERROR: create guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE=true" /tmp/ssentinel-create-guardrail.log

echo "===== create operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true bash scripts/run-gitops-real-pr-create.sh "$PR_PREFLIGHT" >/tmp/ssentinel-create-operation-guardrail.log 2>&1; then
  echo "ERROR: create operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr" /tmp/ssentinel-create-operation-guardrail.log

echo "===== create wrong-operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr bash scripts/run-gitops-real-pr-create.sh "$PR_PREFLIGHT" >/tmp/ssentinel-create-wrong-operation-guardrail.log 2>&1; then
  echo "ERROR: create wrong-operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr" /tmp/ssentinel-create-wrong-operation-guardrail.log

echo "===== cleanup guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=false bash scripts/run-gitops-real-pr-cleanup.sh "$CREATE_JSON" >/tmp/ssentinel-cleanup-guardrail.log 2>&1; then
  echo "ERROR: cleanup guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_ALLOW_GITHUB_WRITE=true" /tmp/ssentinel-cleanup-guardrail.log

echo "===== cleanup operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true bash scripts/run-gitops-real-pr-cleanup.sh "$CREATE_JSON" >/tmp/ssentinel-cleanup-operation-guardrail.log 2>&1; then
  echo "ERROR: cleanup operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr" /tmp/ssentinel-cleanup-operation-guardrail.log

echo "===== cleanup wrong-operation guardrail ====="
if S_SENTINEL_ALLOW_GITHUB_WRITE=true S_SENTINEL_GITHUB_WRITE_OPERATION=push-branch bash scripts/run-gitops-real-pr-cleanup.sh "$CREATE_JSON" >/tmp/ssentinel-cleanup-wrong-operation-guardrail.log 2>&1; then
  echo "ERROR: cleanup wrong-operation guardrail did not block" >&2
  exit 1
fi

grep -q "S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr" /tmp/ssentinel-cleanup-wrong-operation-guardrail.log

echo "PASS test-gitops-real-pr-controlled-write-guardrails"
