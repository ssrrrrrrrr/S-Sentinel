#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_ID="$(date +%Y%m%d%H%M%S)"
TMP_DIR=".tmp/test-gitops-real-pr-local-flow-$RUN_ID"
WORKSPACE_BASE="/tmp/s-sentinel-gitops-real-pr-local-flow-$RUN_ID"
BRANCH="ssentinel/local-flow-$RUN_ID"

rm -rf "$TMP_DIR" "$WORKSPACE_BASE"
mkdir -p "$TMP_DIR/package"

cat > "$TMP_DIR/package/package-manifest.json" <<JSON
{
  "schemaVersion": "gitops.adapter.provider.package/v1alpha1",
  "payloadStatus": "PAYLOAD_READY",
  "branchName": "$BRANCH",
  "commitPayloadPath": "$TMP_DIR/package/commit-payload.json"
}
JSON

cat > "$TMP_DIR/package/commit-payload.json" <<JSON
{
  "schemaVersion": "gitops.adapter.commit.payload/v1alpha1",
  "branchName": "$BRANCH",
  "commitMessage": "chore(gitops): local real-pr flow smoke $RUN_ID",
  "pullRequestTitle": "[S Sentinel] Local real PR flow smoke $RUN_ID",
  "patchEntries": [
    {
      "entryId": "entry-1",
      "targetRef": "docs/gitops-real-pr-local-flow-smoke-$RUN_ID.md",
      "changeType": "smoke_test_file",
      "content": "# GitOps Real PR Local Flow Smoke\\n\\nrunId: $RUN_ID\\n\\nThis file is committed locally only. No push or PR is created.\\n"
    }
  ]
}
JSON

cat > "$TMP_DIR/gitops-adapter-provider-result-ready.json" <<JSON
{
  "schemaVersion": "gitops.adapter.provider.result/v1alpha1",
  "gitopsAdapterProviderResultId": "gprs-local-flow-$RUN_ID",
  "release": {
    "releaseId": "local-flow-$RUN_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "providerResult": {
    "resultStatus": "PROVIDER_RESULT_READY",
    "providerType": "github-pr",
    "branchName": "$BRANCH",
    "packageDir": "$TMP_DIR/package",
    "packageManifestPath": "$TMP_DIR/package/package-manifest.json"
  },
  "guardrails": {
    "readOnly": false,
    "dryRunOnly": false,
    "willExecute": false,
    "doesNotCommit": false,
    "doesNotPush": false,
    "doesNotCreatePullRequest": false,
    "doesNotCallExternalGitProvider": true,
    "doesNotModifyKubernetes": true
  }
}
JSON

PLAN="$(bash scripts/build-gitops-real-pr-plan.sh "$TMP_DIR/gitops-adapter-provider-result-ready.json")"
GITOPS_REAL_PR_WORKSPACE_BASE_DIR="$WORKSPACE_BASE" bash scripts/build-gitops-real-pr-workspace.sh "$PLAN" >/dev/null

WORKSPACE_JSON="$TMP_DIR/gitops-real-pr-workspace-local-flow-$RUN_ID.json"
readarray -t INFO < <(bash scripts/run-gitops-real-pr-clone.sh "$WORKSPACE_JSON")

WORKSPACE_DIR="${INFO[0]}"
REPO_DIR="${INFO[1]}"
BRANCH_NAME="${INFO[2]}"

git clone https://github.com/ssrrrrrrrr/S-Sentinel.git "$REPO_DIR" >/dev/null 2>&1
git -C "$REPO_DIR" checkout -b "$BRANCH_NAME" >/dev/null

MAT="$(bash scripts/build-gitops-real-pr-materialization.sh "$WORKSPACE_JSON")"
FILES="$(bash scripts/run-gitops-real-pr-materialize-files.sh "$MAT")"
COMMIT="$(bash scripts/run-gitops-real-pr-local-commit.sh "$MAT" | tail -n 1)"
PUSH_PF="$(bash scripts/build-gitops-real-pr-push-preflight.sh "$COMMIT")"

python3 - "$PLAN" "$MAT" "$FILES" "$COMMIT" "$PUSH_PF" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
mat = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8-sig"))
files = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"))
commit = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8-sig"))
push_pf = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8-sig"))

assert plan["plan"]["planStatus"] == "READY_FOR_REAL_PR"
assert mat["materialization"]["materializationStatus"] == "READY_TO_MATERIALIZE"
assert files["fileMaterialization"]["status"] == "FILES_MATERIALIZED"
assert commit["localCommit"]["commitStatus"] == "LOCAL_COMMIT_CREATED"
assert push_pf["pushPreflight"]["preflightStatus"] == "READY_TO_PUSH_BRANCH"
assert push_pf["pushPreflight"]["remoteBranchExists"] is False

print("PASS local real-pr flow")
PY

echo "PASS test-gitops-real-pr-local-flow"
