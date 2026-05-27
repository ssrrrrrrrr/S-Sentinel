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
  ],
  "targetRepository": {
    "provider": "github",
    "owner": "ssrrrrrrrr",
    "repo": "S-Sentinel",
    "fullName": "ssrrrrrrrr/S-Sentinel",
    "cloneUrl": "https://github.com/ssrrrrrrrr/S-Sentinel.git",
    "baseBranch": "main",
    "authMode": "gh-cli"
  }
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
    "packageManifestPath": "$TMP_DIR/package/package-manifest.json",
    "targetRepository": {
      "provider": "github",
      "owner": "ssrrrrrrrr",
      "repo": "S-Sentinel",
      "fullName": "ssrrrrrrrr/S-Sentinel",
      "cloneUrl": "https://github.com/ssrrrrrrrr/S-Sentinel.git",
      "baseBranch": "main",
      "authMode": "gh-cli"
    }
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

CLONE_URL="$(python3 - "$WORKSPACE_JSON" <<'PY2'
import json
import sys
from pathlib import Path

workspace = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
target = workspace.get("targetRepository") or {}
clone_url = target.get("cloneUrl") or ""
if not clone_url:
    raise SystemExit("ERROR: workspace.targetRepository.cloneUrl is missing")
print(clone_url)
PY2
)"

git clone "$CLONE_URL" "$REPO_DIR" >/dev/null 2>&1
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

assert files["guardrails"]["willExecute"] is True
assert files["guardrails"]["didMaterializeFiles"] is True
assert files["guardrails"]["doesNotCommit"] is True
assert files["guardrails"]["doesNotPush"] is True

assert commit["guardrails"]["willExecute"] is True
assert commit["guardrails"]["didCreateLocalCommit"] is True
assert commit["guardrails"]["doesNotPush"] is True
assert commit["guardrails"]["doesNotCreatePullRequest"] is True

assert push_pf["guardrails"]["willExecute"] is False
assert push_pf["guardrails"]["doesNotPush"] is True

for name, obj in [
    ("plan", plan),
    ("materialization", mat),
    ("fileMaterialization", files),
    ("localCommit", commit),
    ("pushPreflight", push_pf),
]:
    target = obj.get("targetRepository") or {}
    assert target.get("fullName") == "ssrrrrrrrr/S-Sentinel", (name, target)
    assert target.get("baseBranch") == "main", (name, target)
    assert target.get("authMode") == "gh-cli", (name, target)

print("PASS local real-pr flow")
PY

echo "PASS test-gitops-real-pr-local-flow"
