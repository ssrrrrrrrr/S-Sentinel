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

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-gitops-adapter-pickup-ack-test}"
REPORT_DIR="$TMP_DIR/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

RELEASE_ID="20260101-191919"
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
cat > "$WORKSPACE_DIR/pickup-control.json" <<'JSON'
{"kind":"pickup-control"}
JSON
cat > "$WORKSPACE_DIR/pickup-summary.md" <<'MD'
# Pickup Summary
MD

cat > "$REPORT_DIR/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-gitops-adapter-pickup-ack.sh",
  "releaseId": "$RELEASE_ID",
  "generatedAt": "2026-01-01T19:19:19Z",
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
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json",
    "gitopsAdapterRun": "gitops-adapter-run-$RELEASE_ID.json",
    "gitopsAdapterPickup": "gitops-adapter-pickup-$RELEASE_ID.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gad-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-pickup-ack.sh",
  "generatedAt": "2026-01-01T19:19:20Z",
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
  "generatedBy": "test-gitops-adapter-pickup-ack.sh",
  "generatedAt": "2026-01-01T19:19:21Z",
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
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json"
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
      "generatedAt": "2026-01-01T19:19:21Z",
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

cat > "$REPORT_DIR/gitops-adapter-pickup-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup/v1alpha1",
  "gitopsAdapterPickupId": "gpick-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-pickup-ack.sh",
  "generatedAt": "2026-01-01T19:19:22Z",
  "mode": "local_gitops_adapter_pickup",
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
    "gitopsAdapterRun": "gitops-adapter-run-$RELEASE_ID.json",
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json"
  },
  "pickup": {
    "pickupStatus": "READY_FOR_PICKUP",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "$WORKSPACE_DIR",
    "branchName": "ssentinel/$RELEASE_ID",
    "workspaceFiles": [
      {"fileId": "manifest", "workspacePath": "$WORKSPACE_DIR/manifest.json", "exists": true, "contentType": "application/json", "description": "manifest"}
    ],
    "pickupControl": {
      "path": "$WORKSPACE_DIR/pickup-control.json",
      "summaryPath": "$WORKSPACE_DIR/pickup-summary.md",
      "generatedAt": "2026-01-01T19:19:22Z",
      "localOnly": true
    },
    "nextCheckpoint": "human_pickup_workspace_review",
    "nextActor": "service_owner_or_release_operator",
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

echo "===== build gitops adapter pickup ack ====="
./scripts/build-gitops-adapter-pickup-ack.sh "$REPORT_DIR/release-evidence-$RELEASE_ID.json" > "$TMP_DIR/pickup-ack.log"
cat "$TMP_DIR/pickup-ack.log"

echo
echo "===== assert gitops adapter pickup ack ====="
"$PYTHON_BIN" - "$REPORT_DIR/release-evidence-$RELEASE_ID.json" "$REPORT_DIR/gitops-adapter-pickup-ack-$RELEASE_ID.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ack = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert ack["schemaVersion"] == "gitops.adapter.pickup.ack/v1alpha1"
assert ack["gitopsAdapterPickupAckId"] == "gack-20260101-191919"
assert ack["acknowledgement"]["ackStatus"] == "WAITING_FOR_ACK"
assert ack["acknowledgement"]["pickupStatus"] == "READY_FOR_PICKUP"
assert ack["acknowledgement"]["nextCheckpoint"] == "acknowledge_pickup_workspace"
assert ack["acknowledgement"]["assignedActor"] == "service_owner_or_release_operator"
assert Path(ack["acknowledgement"]["ackControl"]["path"]).exists()
assert Path(ack["acknowledgement"]["ackControl"]["summaryPath"]).exists()
assert evidence["gitopsAdapterPickupAckId"] == "gack-20260101-191919"
assert evidence["decisionRefs"]["gitopsAdapterPickupAck"]["ackStatus"] == "WAITING_FOR_ACK"

print("PASS: gitops adapter pickup ack generated and linked")
PY

echo
echo "===== validate contracts ====="
"$PYTHON_BIN" ./scripts/validate-release-contracts.py \
  "$REPORT_DIR/release-evidence-$RELEASE_ID.json" \
  "$REPORT_DIR/gitops-adapter-pickup-ack-$RELEASE_ID.json"

echo
echo "PASS: gitops adapter pickup ack test passed"
