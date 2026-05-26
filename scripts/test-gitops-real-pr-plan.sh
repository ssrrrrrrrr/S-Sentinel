#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-gitops-real-pr-plan"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/package"

cat > "$TMP_DIR/package/package-manifest.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.provider.package/v1alpha1",
  "payloadStatus": "PAYLOAD_READY",
  "branchName": "ssentinel/demo-app-dev-stop-promotion-test",
  "commitPayloadPath": ".tmp/test-gitops-real-pr-plan/package/commit-payload.json"
}
JSON

cat > "$TMP_DIR/package/commit-payload.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.commit.payload/v1alpha1",
  "branchName": "ssentinel/demo-app-dev-stop-promotion-test",
  "commitMessage": "chore(gitops): prepare STOP_PROMOTION for demo-app [test]",
  "pullRequestTitle": "[S Sentinel] STOP_PROMOTION for demo-app (dev)",
  "patchEntries": [
    {
      "entryId": "entry-1",
      "targetRef": "deploy/overlays/dev/rollout.yaml",
      "changeType": "rendered_manifest_update"
    }
  ]
}
JSON

cat > "$TMP_DIR/gitops-adapter-provider-result-ready.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.provider.result/v1alpha1",
  "gitopsAdapterProviderResultId": "gprs-test-ready",
  "release": {
    "releaseId": "test-ready",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "providerResult": {
    "resultStatus": "PROVIDER_RESULT_READY",
    "providerType": "github-pr",
    "branchName": "ssentinel/demo-app-dev-stop-promotion-test",
    "packageDir": ".tmp/test-gitops-real-pr-plan/package",
    "packageManifestPath": ".tmp/test-gitops-real-pr-plan/package/package-manifest.json"
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

echo "===== ready case ====="
READY_OUT="$(bash scripts/build-gitops-real-pr-plan.sh "$TMP_DIR/gitops-adapter-provider-result-ready.json")"
cat "$READY_OUT"

python3 - "$READY_OUT" <<'PY'
import json, sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
plan = data["plan"]

assert plan["planStatus"] == "READY_FOR_REAL_PR", plan
assert plan["branchName"] == "ssentinel/demo-app-dev-stop-promotion-test", plan
assert plan["patchEntryCount"] == 1, plan

print("PASS ready case")
PY

echo "PASS test-gitops-real-pr-plan"
