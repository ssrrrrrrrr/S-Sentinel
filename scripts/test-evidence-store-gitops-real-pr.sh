#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPORT_DIR=".tmp/test-evidence-store-gitops-real-pr-report"
DB_PATH=".tmp/test-evidence-store-gitops-real-pr.sqlite"

rm -rf "$REPORT_DIR"
rm -f "$DB_PATH"
mkdir -p "$REPORT_DIR"

cat > "$REPORT_DIR/gitops-real-pr-create-evidence-store-smoke.json" <<'JSON'
{
  "schemaVersion": "gitops.real.pr.create/v1alpha1",
  "gitopsRealPRCreateId": "gprcreate-evidence-store-smoke",
  "release": {
    "releaseId": "evidence-store-real-pr-smoke",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "pullRequest": {
    "createStatus": "PULL_REQUEST_CREATED",
    "repo": "ssrrrrrrrr/S-Sentinel",
    "number": 7,
    "state": "OPEN",
    "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
    "headRefName": "ssentinel/evidence-store-real-pr-smoke",
    "baseRefName": "main",
    "mergeStateStatus": "CLEAN"
  },
  "guardrails": {
    "readOnly": false,
    "dryRunOnly": false,
    "willExecute": true,
    "didCreatePullRequest": true,
    "doesNotCommit": true,
    "doesNotPush": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  },
  "writeGate": {
    "enabled": true,
    "allowEnv": "S_SENTINEL_ALLOW_GITHUB_WRITE",
    "allowValue": "true",
    "operationEnv": "S_SENTINEL_GITHUB_WRITE_OPERATION",
    "requiredOperation": "create-pr",
    "operation": "create-pr"
  }
}
JSON

cat > "$REPORT_DIR/gitops-real-pr-cleanup-evidence-store-smoke.json" <<'JSON'
{
  "schemaVersion": "gitops.real.pr.cleanup/v1alpha1",
  "gitopsRealPRCleanupId": "gprcleanup-evidence-store-smoke",
  "release": {
    "releaseId": "evidence-store-real-pr-smoke",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "cleanup": {
    "cleanupStatus": "CLEANED_UP",
    "pullRequest": {
      "number": 7,
      "state": "CLOSED",
      "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
      "headRefName": "ssentinel/evidence-store-real-pr-smoke",
      "baseRefName": "main"
    },
    "remoteBranchExists": false,
    "remoteHeads": []
  },
  "guardrails": {
    "readOnly": false,
    "dryRunOnly": false,
    "willExecute": true,
    "didClosePullRequest": true,
    "didDeleteRemoteBranch": true,
    "doesNotCommit": true,
    "doesNotCreatePullRequest": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  },
  "writeGate": {
    "enabled": true,
    "allowEnv": "S_SENTINEL_ALLOW_GITHUB_WRITE",
    "allowValue": "true",
    "operationEnv": "S_SENTINEL_GITHUB_WRITE_OPERATION",
    "requiredOperation": "cleanup-pr",
    "operation": "cleanup-pr"
  }
}
JSON

echo "===== init db ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null

echo "===== import real-pr evidence fixtures ====="
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$REPORT_DIR"

echo "===== search gitopsRealPRCreate ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type gitopsRealPRCreate \
  --release-id evidence-store-real-pr-smoke \
  --limit 10 \
  >/tmp/ssentinel-real-pr-create-search.json
cat /tmp/ssentinel-real-pr-create-search.json

echo "===== search gitopsRealPRCleanup ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type gitopsRealPRCleanup \
  --release-id evidence-store-real-pr-smoke \
  --limit 10 \
  >/tmp/ssentinel-real-pr-cleanup-search.json
cat /tmp/ssentinel-real-pr-cleanup-search.json

echo "===== assert summaries ====="
python3 - <<'PY'
import json
from pathlib import Path

create = json.loads(Path("/tmp/ssentinel-real-pr-create-search.json").read_text())
cleanup = json.loads(Path("/tmp/ssentinel-real-pr-cleanup-search.json").read_text())

create_items = create.get("items") or create.get("objects") or []
cleanup_items = cleanup.get("items") or cleanup.get("objects") or []

assert create_items, create
assert cleanup_items, cleanup

create_summary = create_items[0].get("summary") or {}
cleanup_summary = cleanup_items[0].get("summary") or {}

assert create_summary.get("createStatus") == "PULL_REQUEST_CREATED", create_summary
assert create_summary.get("pullRequestNumber") == 7, create_summary
assert create_summary.get("pullRequestState") == "OPEN", create_summary
assert create_summary.get("branchName") == "ssentinel/evidence-store-real-pr-smoke", create_summary
assert create_summary.get("willExecute") is True, create_summary
assert create_summary.get("readOnly") is False, create_summary
assert create_summary.get("dryRunOnly") is False, create_summary
assert create_summary.get("didCreatePullRequest") is True, create_summary
assert create_summary.get("doesNotMergePullRequest") is True, create_summary
assert create_summary.get("doesNotModifyKubernetes") is True, create_summary
assert create_summary.get("writeGateEnabled") is True, create_summary
assert create_summary.get("writeGateRequiredOperation") == "create-pr", create_summary
assert create_summary.get("writeGateOperation") == "create-pr", create_summary

assert cleanup_summary.get("cleanupStatus") == "CLEANED_UP", cleanup_summary
assert cleanup_summary.get("pullRequestState") == "CLOSED", cleanup_summary
assert cleanup_summary.get("remoteBranchExists") is False, cleanup_summary
assert cleanup_summary.get("branchName") == "ssentinel/evidence-store-real-pr-smoke", cleanup_summary
assert cleanup_summary.get("willExecute") is True, cleanup_summary
assert cleanup_summary.get("readOnly") is False, cleanup_summary
assert cleanup_summary.get("dryRunOnly") is False, cleanup_summary
assert cleanup_summary.get("didClosePullRequest") is True, cleanup_summary
assert cleanup_summary.get("didDeleteRemoteBranch") is True, cleanup_summary
assert cleanup_summary.get("doesNotMergePullRequest") is True, cleanup_summary
assert cleanup_summary.get("doesNotModifyKubernetes") is True, cleanup_summary
assert cleanup_summary.get("writeGateEnabled") is True, cleanup_summary
assert cleanup_summary.get("writeGateRequiredOperation") == "cleanup-pr", cleanup_summary
assert cleanup_summary.get("writeGateOperation") == "cleanup-pr", cleanup_summary

print("PASS evidence-store gitops real-pr import/search")
PY
