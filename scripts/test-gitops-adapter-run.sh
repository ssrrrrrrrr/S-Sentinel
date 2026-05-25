#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python runtime not found. Set PYTHON_BIN=/path/to/python." >&2
    exit 1
  fi
fi

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-gitops-adapter-run-test}"
REPORT_DIR="$TMP_DIR/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

RELEASE_ID="20260101-151515"
WORKSPACE_DIR="$REPORT_DIR/gitops-handoff-$RELEASE_ID"
mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/manifest.json" <<'JSON'
{"kind":"handoff-manifest"}
JSON
cat > "$WORKSPACE_DIR/pickup-instructions.md" <<'MD'
# Pickup Instructions
MD
cat > "$WORKSPACE_DIR/patch-entries.json" <<'JSON'
{"entries":[{"file":"kustomization.yaml"}]}
JSON
cat > "$WORKSPACE_DIR/pull-request.md" <<'MD'
# Pull Request
MD
cat > "$WORKSPACE_DIR/handoff-checklist.md" <<'MD'
# Checklist
MD

cat > "$REPORT_DIR/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-gitops-adapter-run.sh",
  "releaseId": "$RELEASE_ID",
  "generatedAt": "2026-01-01T15:15:15Z",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "executionMode": "manual_approval",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "summary": {
    "riskLevel": "high",
    "riskScore": 88,
    "rolloutPhase": "Paused",
    "rolloutAbort": false,
    "analysisRunPhase": "Running",
    "matchedPolicyRules": ["signed_release_gate_requires_human_approval"],
    "failedMetrics": ["error-rate"]
  },
  "artifacts": {
    "gitopsAdapterRequest": "gitops-adapter-request-$RELEASE_ID.json",
    "gitopsAdapterResult": "gitops-adapter-result-$RELEASE_ID.json",
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-request-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.request/v1alpha1",
  "gitopsAdapterRequestId": "ga-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-run.sh",
  "generatedAt": "2026-01-01T15:15:16Z",
  "mode": "review_only_gitops_adapter_request",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "requestedAction": "STOP_PROMOTION"
  },
  "request": {
    "requestStatus": "WAITING_APPROVAL",
    "adapterType": "gitops-handoff-local",
    "requestedOperation": "prepare_review_handoff_delivery",
    "delivery": {
      "branchName": "ssentinel/$RELEASE_ID"
    },
    "handoffFiles": [
      {"fileId": "manifest", "path": "manifest.json", "contentType": "application/json", "description": "manifest"},
      {"fileId": "patches", "path": "patch-entries.json", "contentType": "application/json", "description": "patch entries"},
      {"fileId": "pr-body", "path": "pull-request.md", "contentType": "text/markdown", "description": "pr body"},
      {"fileId": "checklist", "path": "handoff-checklist.md", "contentType": "text/markdown", "description": "checklist"}
    ],
    "summary": "adapter request"
  },
  "guardrails": {
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false,
    "doesNotModifyGitOps": true,
    "doesNotCommit": true,
    "doesNotPush": true,
    "doesNotCreatePullRequest": true,
    "doesNotModifyKubernetes": true
  }
}
JSON

cat > "$REPORT_DIR/gitops-adapter-result-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.result/v1alpha1",
  "gitopsAdapterResultId": "gar-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-run.sh",
  "generatedAt": "2026-01-01T15:15:17Z",
  "mode": "local_gitops_adapter_result",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "requestedAction": "STOP_PROMOTION"
  },
  "delivery": {
    "deliveryStatus": "WAITING_APPROVAL",
    "requestedOperation": "prepare_review_handoff_delivery",
    "receipt": {
      "branchName": "ssentinel/$RELEASE_ID"
    },
    "outputFiles": [
      {"fileId": "manifest", "path": "manifest.json"},
      {"fileId": "patches", "path": "patch-entries.json"},
      {"fileId": "pr-body", "path": "pull-request.md"},
      {"fileId": "checklist", "path": "handoff-checklist.md"}
    ]
  },
  "adapter": {
    "adapterType": "gitops-handoff-local",
    "willExecute": false
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

cat > "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gad-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-run.sh",
  "generatedAt": "2026-01-01T15:15:18Z",
  "mode": "local_gitops_adapter_delivery",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "requestedAction": "STOP_PROMOTION"
  },
  "delivery": {
    "deliveryStatus": "WORKSPACE_READY",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "$WORKSPACE_DIR",
    "branchName": "ssentinel/$RELEASE_ID",
    "manifestFile": "$WORKSPACE_DIR/manifest.json",
    "pickupInstructionsFile": "$WORKSPACE_DIR/pickup-instructions.md",
    "copiedFiles": [
      {"fileId": "manifest", "workspacePath": "$WORKSPACE_DIR/manifest.json", "contentType": "application/json", "description": "manifest"},
      {"fileId": "patches", "workspacePath": "$WORKSPACE_DIR/patch-entries.json", "contentType": "application/json", "description": "patch entries"},
      {"fileId": "pr-body", "workspacePath": "$WORKSPACE_DIR/pull-request.md", "contentType": "text/markdown", "description": "pr body"},
      {"fileId": "checklist", "workspacePath": "$WORKSPACE_DIR/handoff-checklist.md", "contentType": "text/markdown", "description": "checklist"}
    ],
    "warnings": []
  },
  "adapter": {
    "adapterType": "gitops-handoff-local",
    "willExecute": false
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

echo "===== build gitops adapter run ====="
./scripts/build-gitops-adapter-run.sh "$REPORT_DIR/release-evidence-$RELEASE_ID.json" > "$TMP_DIR/run.log"
cat "$TMP_DIR/run.log"

echo
echo "===== assert gitops adapter run ====="
"$PYTHON_BIN" - "$REPORT_DIR/release-evidence-$RELEASE_ID.json" "$REPORT_DIR/gitops-adapter-run-$RELEASE_ID.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
run = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert run["schemaVersion"] == "gitops.adapter.run/v1alpha1"
assert run["gitopsAdapterRunId"] == "grun-20260101-151515"
assert run["run"]["runStatus"] == "HANDOFF_READY"
assert len(run["run"]["workspaceFiles"]) == 4
assert Path(run["run"]["pickupReceipt"]["path"]).exists()
assert Path(run["run"]["pickupReceipt"]["summaryPath"]).exists()
assert evidence["gitopsAdapterRunId"] == "grun-20260101-151515"
assert evidence["decisionRefs"]["gitopsAdapterRun"]["workspaceFileCount"] == 4

print("PASS: gitops adapter run generated and linked")
PY

echo
echo "===== validate contracts ====="
"$PYTHON_BIN" ./scripts/validate-release-contracts.py \
  "$REPORT_DIR/release-evidence-$RELEASE_ID.json" \
  "$REPORT_DIR/gitops-adapter-run-$RELEASE_ID.json"

echo
echo "PASS: gitops adapter run test passed"
