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

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-gitops-adapter-pickup-test}"
REPORT_DIR="$TMP_DIR/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

RELEASE_ID="20260101-181818"
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
cat > "$WORKSPACE_DIR/adapter-run-receipt.json" <<'JSON'
{"kind":"adapter-run-receipt"}
JSON
cat > "$WORKSPACE_DIR/adapter-run-summary.md" <<'MD'
# Adapter Run Summary
MD

cat > "$REPORT_DIR/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-gitops-adapter-pickup.sh",
  "releaseId": "$RELEASE_ID",
  "generatedAt": "2026-01-01T18:18:18Z",
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
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json",
    "gitopsAdapterRun": "gitops-adapter-run-$RELEASE_ID.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-request-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.request/v1alpha1",
  "gitopsAdapterRequestId": "ga-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-pickup.sh",
  "generatedAt": "2026-01-01T18:18:19Z",
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
      {"fileId": "manifest", "path": "manifest.json", "contentType": "application/json", "description": "manifest"}
    ]
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

cat > "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gad-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-pickup.sh",
  "generatedAt": "2026-01-01T18:18:20Z",
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

cat > "$REPORT_DIR/gitops-adapter-run-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.run/v1alpha1",
  "gitopsAdapterRunId": "grun-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-pickup.sh",
  "generatedAt": "2026-01-01T18:18:21Z",
  "mode": "local_gitops_adapter_run",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "requestedAction": "STOP_PROMOTION"
  },
  "inputs": {
    "releaseEvidence": "release-evidence-$RELEASE_ID.json",
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json",
    "gitopsAdapterResult": null,
    "gitopsAdapterRequest": "gitops-adapter-request-$RELEASE_ID.json"
  },
  "adapter": {
    "adapter": "gitops-handoff-local",
    "adapterType": "gitops-handoff-local",
    "runMode": "local_handoff_readiness",
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false,
    "doesNotCallExternalGitProvider": true
  },
  "run": {
    "runStatus": "HANDOFF_READY",
    "workspaceDir": "$WORKSPACE_DIR",
    "requestedOperation": "prepare_review_handoff_delivery",
    "branchName": "ssentinel/$RELEASE_ID",
    "summary": "workspace validated",
    "checks": [
      {"checkId": "workspace_dir_exists", "title": "Workspace directory exists", "status": "PASS"}
    ],
    "pickupReceipt": {
      "path": "$WORKSPACE_DIR/adapter-run-receipt.json",
      "summaryPath": "$WORKSPACE_DIR/adapter-run-summary.md",
      "generatedAt": "2026-01-01T18:18:21Z",
      "localOnly": true
    },
    "workspaceFiles": [
      {"fileId": "manifest", "workspacePath": "$WORKSPACE_DIR/manifest.json", "exists": true, "contentType": "application/json", "description": "manifest"},
      {"fileId": "patches", "workspacePath": "$WORKSPACE_DIR/patch-entries.json", "exists": true, "contentType": "application/json", "description": "patch entries"},
      {"fileId": "pr-body", "workspacePath": "$WORKSPACE_DIR/pull-request.md", "exists": true, "contentType": "text/markdown", "description": "pr body"},
      {"fileId": "checklist", "workspacePath": "$WORKSPACE_DIR/handoff-checklist.md", "exists": true, "contentType": "text/markdown", "description": "checklist"}
    ],
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

echo "===== build gitops adapter pickup ====="
./scripts/build-gitops-adapter-pickup.sh "$REPORT_DIR/release-evidence-$RELEASE_ID.json" > "$TMP_DIR/pickup.log"
cat "$TMP_DIR/pickup.log"

echo
echo "===== assert gitops adapter pickup ====="
"$PYTHON_BIN" - "$REPORT_DIR/release-evidence-$RELEASE_ID.json" "$REPORT_DIR/gitops-adapter-pickup-$RELEASE_ID.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pickup = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert pickup["schemaVersion"] == "gitops.adapter.pickup/v1alpha1"
assert pickup["gitopsAdapterPickupId"] == "gpick-20260101-181818"
assert pickup["pickup"]["pickupStatus"] == "READY_FOR_PICKUP"
assert pickup["pickup"]["nextCheckpoint"] == "human_pickup_workspace_review"
assert pickup["pickup"]["nextActor"] == "service_owner_or_release_operator"
assert Path(pickup["pickup"]["pickupControl"]["path"]).exists()
assert Path(pickup["pickup"]["pickupControl"]["summaryPath"]).exists()
assert evidence["gitopsAdapterPickupId"] == "gpick-20260101-181818"
assert evidence["decisionRefs"]["gitopsAdapterPickup"]["pickupStatus"] == "READY_FOR_PICKUP"

print("PASS: gitops adapter pickup generated and linked")
PY

echo
echo "===== validate contracts ====="
"$PYTHON_BIN" ./scripts/validate-release-contracts.py \
  "$REPORT_DIR/release-evidence-$RELEASE_ID.json" \
  "$REPORT_DIR/gitops-adapter-pickup-$RELEASE_ID.json"

echo
echo "PASS: gitops adapter pickup test passed"
