#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$ROOT_DIR/.tmp/test-gitops-adapter-provider-result"
REPORT_DIR="$TEST_DIR/reports"

rm -rf "$TEST_DIR"
mkdir -p "$REPORT_DIR"

cat > "$REPORT_DIR/release-evidence-demo.json" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test",
  "releaseId": "demo",
  "service": "demo-app",
  "env": "staging",
  "namespace": "demo",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "PROMOTE",
  "releaseResult": "healthy",
  "executionMode": "manual_approval",
  "requiresHumanApproval": true,
  "safeToRetry": true,
  "summary": {
    "rolloutPhase": "Paused",
    "rolloutAbort": false,
    "analysisRunPhase": "Successful",
    "riskLevel": "medium",
    "riskScore": 42,
    "failedMetrics": [],
    "matchedPolicyRules": []
  },
  "artifacts": {
    "releaseContext": null,
    "aiDecision": null,
    "policyDecision": null,
    "releaseSummary": null,
    "actionPlan": null,
    "gitopsAdapterDispatch": ".tmp/test-gitops-adapter-provider-result/reports/gitops-adapter-dispatch-demo.json",
    "gitopsAdapterPayload": ".tmp/test-gitops-adapter-provider-result/reports/gitops-adapter-payload-demo.json",
    "gitopsAdapterProviderRequest": ".tmp/test-gitops-adapter-provider-result/reports/gitops-adapter-provider-request-demo.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-dispatch-demo.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.dispatch/v1alpha1",
  "gitopsAdapterDispatchId": "gdisp-demo",
  "generatedBy": "test",
  "generatedAt": "2026-05-26T00:00:00Z",
  "mode": "external_gitops_adapter_stub_dispatch",
  "dispatch": {
    "dispatchStatus": "STUB_DISPATCHED",
    "payloadStatus": "PAYLOAD_READY",
    "branchName": "ssentinel/demo-promote",
    "requestedOperation": "open_gitops_pr",
    "payloadDir": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo",
    "payloadManifestPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/payload-manifest.json",
    "commitPayloadPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/commit-payload.json",
    "providerRequestPath": ".tmp/test-gitops-adapter-provider-result/reports/provider-docs/provider-request.json",
    "patchEntryCount": 2,
    "workspaceArtifactCount": 4,
    "warnings": []
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

mkdir -p "$REPORT_DIR/payload-demo" "$REPORT_DIR/provider-docs"

cat > "$REPORT_DIR/payload-demo/payload-manifest.json" <<'JSON'
{
  "path": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/payload-manifest.json",
  "commitPayloadPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/commit-payload.json"
}
JSON

cat > "$REPORT_DIR/payload-demo/commit-payload.json" <<'JSON'
{
  "commitMessage": "chore: promote demo release",
  "pullRequestTitle": "Promote demo release"
}
JSON

cat > "$REPORT_DIR/gitops-adapter-payload-demo.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.payload/v1alpha1",
  "gitopsAdapterPayloadId": "gpay-demo",
  "generatedBy": "test",
  "generatedAt": "2026-05-26T00:00:00Z",
  "mode": "local_gitops_adapter_payload",
  "payload": {
    "payloadStatus": "PAYLOAD_READY",
    "progressStatus": "HANDOFF_COMPLETED",
    "branchName": "ssentinel/demo-promote",
    "requestedOperation": "open_gitops_pr",
    "workspaceDir": ".tmp/test-gitops-adapter-provider-result/reports/workspace-demo",
    "bundleDir": ".tmp/test-gitops-adapter-provider-result/reports/bundle-demo",
    "patchEntryCount": 2,
    "handoffFileCount": 3,
    "workspaceArtifactCount": 4,
    "payloadManifest": {
      "path": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/payload-manifest.json",
      "commitPayloadPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/commit-payload.json"
    }
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

cat > "$REPORT_DIR/provider-docs/provider-request.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.provider.request.document/v1alpha1",
  "pullRequestTitle": "Promote demo release"
}
JSON

cat > "$REPORT_DIR/provider-docs/pull-request-body.md" <<'MD'
# Promote demo release

- automated by S Sentinel
MD

cat > "$REPORT_DIR/gitops-adapter-provider-request-demo.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.provider.request/v1alpha1",
  "gitopsAdapterProviderRequestId": "gprq-demo",
  "generatedBy": "test",
  "generatedAt": "2026-05-26T00:00:00Z",
  "mode": "provider_ready_gitops_pr_request",
  "release": {
    "releaseId": "demo",
    "service": "demo-app",
    "env": "staging",
    "namespace": "demo",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "PROMOTE",
    "requestedAction": "promote"
  },
  "inputs": {
    "releaseEvidence": ".tmp/test-gitops-adapter-provider-result/reports/release-evidence-demo.json",
    "gitopsAdapterDispatch": ".tmp/test-gitops-adapter-provider-result/reports/gitops-adapter-dispatch-demo.json",
    "gitopsAdapterPayload": ".tmp/test-gitops-adapter-provider-result/reports/gitops-adapter-payload-demo.json",
    "gitopsPRBundle": null
  },
  "providerRequest": {
    "requestStatus": "PROVIDER_REQUEST_READY",
    "providerType": "github-pr",
    "branchName": "ssentinel/demo-promote",
    "requestedOperation": "open_gitops_pr",
    "commitMessage": "chore: promote demo release",
    "pullRequestTitle": "Promote demo release",
    "pullRequestBodyPath": ".tmp/test-gitops-adapter-provider-result/reports/provider-docs/pull-request-body.md",
    "payloadManifestPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/payload-manifest.json",
    "commitPayloadPath": ".tmp/test-gitops-adapter-provider-result/reports/payload-demo/commit-payload.json",
    "providerRequestPath": ".tmp/test-gitops-adapter-provider-result/reports/provider-docs/provider-request.json",
    "patchEntryCount": 2,
    "workspaceArtifactCount": 4,
    "labels": ["s-sentinel", "env:staging"],
    "summary": "ready",
    "warnings": []
  },
  "guardrails": {
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false,
    "doesNotModifyGitOps": true,
    "doesNotCommit": true,
    "doesNotPush": true,
    "doesNotCreatePullRequest": true,
    "doesNotCallExternalGitProvider": true,
    "doesNotModifyKubernetes": true
  }
}
JSON

export RELEASE_REPORT_DIR="$REPORT_DIR"
"$ROOT_DIR/scripts/build-gitops-adapter-provider-result.sh" "$REPORT_DIR/release-evidence-demo.json" > "$TEST_DIR/stdout.txt"

OUTPUT_JSON="$REPORT_DIR/gitops-adapter-provider-result-demo.json"
[ -f "$OUTPUT_JSON" ]
"${PYTHON_BIN:-python}" "$ROOT_DIR/scripts/validate-release-contracts.py" "$OUTPUT_JSON"

"${PYTHON_BIN:-python}" - "$OUTPUT_JSON" <<'PY'
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert doc["providerResult"]["resultStatus"] == "PROVIDER_RESULT_READY"
assert doc["providerResult"]["materializedFileCount"] >= 6
assert doc["providerResult"]["branchName"] == "ssentinel/demo-promote"
print("PASS provider result assertions")
PY

echo "PASS test-gitops-adapter-provider-result"
