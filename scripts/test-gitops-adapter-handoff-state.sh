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

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-gitops-adapter-handoff-state-test}"
REPORT_DIR="$TMP_DIR/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

RELEASE_ID="20260101-202020"
WORKSPACE_DIR="$REPORT_DIR/gitops-handoff-$RELEASE_ID"
mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/manifest.json" <<'JSON'
{"kind":"handoff-manifest"}
JSON
cat > "$WORKSPACE_DIR/pickup-instructions.md" <<'MD'
# Pickup Instructions
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
cat > "$WORKSPACE_DIR/pickup-ack-control.json" <<'JSON'
{"kind":"pickup-ack-control"}
JSON
cat > "$WORKSPACE_DIR/pickup-ack-summary.md" <<'MD'
# Pickup Ack Summary
MD

cat > "$REPORT_DIR/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-gitops-adapter-handoff-state.sh",
  "releaseId": "$RELEASE_ID",
  "generatedAt": "2026-01-01T20:20:20Z",
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
    "riskScore": 90,
    "rolloutPhase": "Paused",
    "rolloutAbort": false,
    "analysisRunPhase": "Running",
    "matchedPolicyRules": ["signed_release_gate_requires_human_approval"],
    "failedMetrics": ["error-rate"]
  },
  "artifacts": {
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json",
    "gitopsAdapterRun": "gitops-adapter-run-$RELEASE_ID.json",
    "gitopsAdapterPickup": "gitops-adapter-pickup-$RELEASE_ID.json",
    "gitopsAdapterPickupAck": "gitops-adapter-pickup-ack-$RELEASE_ID.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gad-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-handoff-state.sh",
  "generatedAt": "2026-01-01T20:20:21Z",
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
    "copiedFiles": [],
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
  "generatedBy": "test-gitops-adapter-handoff-state.sh",
  "generatedAt": "2026-01-01T20:20:22Z",
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
      "generatedAt": "2026-01-01T20:20:22Z",
      "localOnly": true
    },
    "workspaceFiles": [],
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
  "generatedBy": "test-gitops-adapter-handoff-state.sh",
  "generatedAt": "2026-01-01T20:20:23Z",
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
    "workspaceFiles": [],
    "pickupControl": {
      "path": "$WORKSPACE_DIR/pickup-control.json",
      "summaryPath": "$WORKSPACE_DIR/pickup-summary.md",
      "generatedAt": "2026-01-01T20:20:23Z",
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

cat > "$REPORT_DIR/gitops-adapter-pickup-ack-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup.ack/v1alpha1",
  "gitopsAdapterPickupAckId": "gack-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-handoff-state.sh",
  "generatedAt": "2026-01-01T20:20:24Z",
  "mode": "local_gitops_adapter_pickup_ack",
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
    "gitopsAdapterPickup": "gitops-adapter-pickup-$RELEASE_ID.json",
    "gitopsAdapterRun": "gitops-adapter-run-$RELEASE_ID.json",
    "gitopsAdapterDelivery": "gitops-adapter-delivery-$RELEASE_ID.json"
  },
  "acknowledgement": {
    "ackStatus": "WAITING_FOR_ACK",
    "pickupStatus": "READY_FOR_PICKUP",
    "branchName": "ssentinel/$RELEASE_ID",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "$WORKSPACE_DIR",
    "assignedActor": "service_owner_or_release_operator",
    "nextCheckpoint": "acknowledge_pickup_workspace",
    "summary": "Pickup acknowledgement is waiting.",
    "ackControl": {
      "path": "$WORKSPACE_DIR/pickup-ack-control.json",
      "summaryPath": "$WORKSPACE_DIR/pickup-ack-summary.md",
      "generatedAt": "2026-01-01T20:20:24Z",
      "localOnly": true
    },
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

echo "===== build gitops adapter handoff state ====="
./scripts/build-gitops-adapter-handoff-state.sh "$REPORT_DIR/release-evidence-$RELEASE_ID.json" > "$TMP_DIR/handoff-state.log"
cat "$TMP_DIR/handoff-state.log"

echo
echo "===== assert gitops adapter handoff state ====="
"$PYTHON_BIN" - "$REPORT_DIR/release-evidence-$RELEASE_ID.json" "$REPORT_DIR/gitops-adapter-handoff-state-$RELEASE_ID.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
state = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert state["schemaVersion"] == "gitops.adapter.handoff.state/v1alpha1"
assert state["gitopsAdapterHandoffStateId"] == "ghs-20260101-202020"
assert state["handoffState"]["stateStatus"] == "READY_FOR_ACKNOWLEDGEMENT"
assert state["handoffState"]["ackStatus"] == "WAITING_FOR_ACK"
assert state["handoffState"]["currentCheckpoint"] == "pickup_ack_pending"
assert state["handoffState"]["nextCheckpoint"] == "acknowledge_pickup_workspace"
assert state["handoffState"]["currentActor"] == "service_owner_or_release_operator"
assert state["handoffState"]["nextActor"] == "service_owner_or_release_operator"
assert Path(state["handoffState"]["stateControl"]["path"]).exists()
assert Path(state["handoffState"]["stateControl"]["summaryPath"]).exists()
assert evidence["gitopsAdapterHandoffStateId"] == "ghs-20260101-202020"
assert evidence["decisionRefs"]["gitopsAdapterHandoffState"]["stateStatus"] == "READY_FOR_ACKNOWLEDGEMENT"

print("PASS: gitops adapter handoff state generated and linked")
PY

echo
echo "===== validate contracts ====="
"$PYTHON_BIN" ./scripts/validate-release-contracts.py \
  "$REPORT_DIR/release-evidence-$RELEASE_ID.json" \
  "$REPORT_DIR/gitops-adapter-handoff-state-$RELEASE_ID.json"

echo
echo "PASS: gitops adapter handoff state test passed"
