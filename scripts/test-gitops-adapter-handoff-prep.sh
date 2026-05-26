#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssentinel-handoff-prep-XXXXXX")"
REPORT_DIR="$TMP_DIR/reports"
mkdir -p "$REPORT_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

release_id="20260526-130000"

cat > "$REPORT_DIR/release-evidence-$release_id.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "fixture",
  "generatedAt": "2026-05-26T13:00:00Z",
  "releaseId": "$release_id",
  "service": "checkout",
  "env": "prod",
  "namespace": "checkout",
  "releaseResult": "degraded",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "INVESTIGATE",
  "executionMode": "manual_approval",
  "requiresHumanApproval": true,
  "safeToRetry": true,
  "summary": {
    "rolloutPhase": "Paused",
    "rolloutAbort": false,
    "analysisRunPhase": "Successful",
    "riskLevel": "medium",
    "riskScore": 52,
    "failedMetrics": [],
    "matchedPolicyRules": ["human-approval-required"]
  },
  "artifacts": {
    "releaseContext": "docs/release-reports/release-context-20260526-130000.json",
    "aiDecision": "docs/release-reports/ai-decision-20260526-130000.json",
    "policyDecision": "docs/release-reports/policy-decision-20260526-130000.json",
    "releaseSummary": null,
    "actionPlan": null,
    "gitopsAdapterPickupTransition": "$REPORT_DIR/gitops-adapter-pickup-transition-$release_id.json",
    "gitopsAdapterPickupEvent": "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json",
    "gitopsAdapterHandoffState": "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json"
  },
  "decisionRefs": {}
}
JSON

mkdir -p "$REPORT_DIR/workspace"
cat > "$REPORT_DIR/workspace/manifest.json" <<JSON
{"kind":"manifest"}
JSON
cat > "$REPORT_DIR/workspace/pull-request.md" <<MD
# PR
MD

cat > "$REPORT_DIR/gitops-adapter-pickup-transition-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup.transition/v1alpha1",
  "gitopsAdapterPickupTransitionId": "gptn-$release_id",
  "generatedBy": "fixture",
  "generatedAt": "2026-05-26T13:00:00Z",
  "mode": "local_gitops_adapter_pickup_transition",
  "release": {
    "releaseId": "$release_id",
    "service": "checkout",
    "env": "prod",
    "namespace": "checkout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "INVESTIGATE"
  },
  "inputs": {
    "releaseEvidence": "$REPORT_DIR/release-evidence-$release_id.json",
    "gitopsAdapterPickupEvent": "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json",
    "gitopsAdapterHandoffState": "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json"
  },
  "pickupTransition": {
    "transitionStatus": "PICKUP_ACCEPTED",
    "eventStatus": "WAITING_FOR_EVENT",
    "handoffStateStatus": "READY_FOR_ACKNOWLEDGEMENT",
    "pickupStatus": "READY_FOR_PICKUP",
    "ackStatus": "WAITING_FOR_ACK",
    "branchName": "ssentinel/$release_id",
    "requestedOperation": "prepare_pr_handoff",
    "workspaceDir": "$REPORT_DIR/workspace",
    "requestedEvent": "ACCEPT_OR_RETURN_PICKUP",
    "selectedEvent": "ACCEPT_PICKUP",
    "allowedEvents": ["ACCEPT_PICKUP", "RETURN_PICKUP"],
    "responseSource": "fixture",
    "resultingStateStatus": "PICKUP_ACCEPTED",
    "currentCheckpoint": "pickup_response_recorded",
    "nextCheckpoint": "prepare_handoff_execution",
    "currentActor": "service_owner_or_release_operator",
    "nextActor": "platform_owner",
    "summary": "fixture",
    "transitionControl": {
      "path": "$REPORT_DIR/workspace/pickup-transition-control.json",
      "summaryPath": "$REPORT_DIR/workspace/pickup-transition-summary.md",
      "generatedAt": "2026-05-26T13:00:00Z",
      "localOnly": true
    }
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

cat > "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup.event/v1alpha1",
  "gitopsAdapterPickupEventId": "gpe-$release_id",
  "generatedBy": "fixture",
  "generatedAt": "2026-05-26T13:00:00Z",
  "mode": "local_gitops_adapter_pickup_event",
  "release": {
    "releaseId": "$release_id",
    "service": "checkout",
    "env": "prod",
    "namespace": "checkout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "INVESTIGATE"
  },
  "pickupEvent": {
    "eventStatus": "WAITING_FOR_EVENT",
    "handoffStateStatus": "READY_FOR_ACKNOWLEDGEMENT",
    "pickupStatus": "READY_FOR_PICKUP",
    "ackStatus": "WAITING_FOR_ACK",
    "branchName": "ssentinel/$release_id",
    "requestedOperation": "prepare_pr_handoff",
    "workspaceDir": "$REPORT_DIR/workspace",
    "currentCheckpoint": "pickup_ack_pending",
    "nextCheckpoint": "await_pickup_event",
    "currentActor": "service_owner_or_release_operator",
    "nextActor": "service_owner_or_release_operator",
    "expectedEvent": "ACCEPT_OR_RETURN_PICKUP",
    "allowedEvents": ["ACCEPT_PICKUP", "RETURN_PICKUP"],
    "summary": "fixture",
    "eventControl": {
      "path": "$REPORT_DIR/workspace/pickup-event-control.json",
      "summaryPath": "$REPORT_DIR/workspace/pickup-event-summary.md",
      "generatedAt": "2026-05-26T13:00:00Z",
      "localOnly": true
    }
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

cat > "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.handoff.state/v1alpha1",
  "gitopsAdapterHandoffStateId": "ghs-$release_id",
  "release": {
    "releaseId": "$release_id",
    "service": "checkout",
    "env": "prod",
    "namespace": "checkout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "INVESTIGATE"
  },
  "handoffState": {
    "stateStatus": "READY_FOR_ACKNOWLEDGEMENT",
    "ackStatus": "WAITING_FOR_ACK",
    "pickupStatus": "READY_FOR_PICKUP",
    "branchName": "ssentinel/$release_id",
    "requestedOperation": "prepare_pr_handoff",
    "workspaceDir": "$REPORT_DIR/workspace",
    "currentCheckpoint": "pickup_ack_pending",
    "nextCheckpoint": "acknowledge_pickup_workspace",
    "currentActor": "service_owner_or_release_operator",
    "nextActor": "service_owner_or_release_operator",
    "summary": "fixture",
    "stateControl": {
      "path": "$REPORT_DIR/workspace/handoff-state-control.json",
      "summaryPath": "$REPORT_DIR/workspace/handoff-state-summary.md",
      "generatedAt": "2026-05-26T13:00:00Z",
      "localOnly": true
    }
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

RELEASE_REPORT_DIR="$REPORT_DIR" \
  "$ROOT_DIR/scripts/build-gitops-adapter-handoff-prep.sh" "$REPORT_DIR/release-evidence-$release_id.json" >/dev/null

python "$ROOT_DIR/scripts/validate-release-contracts.py" \
  "$REPORT_DIR/gitops-adapter-handoff-prep-$release_id.json" \
  "$REPORT_DIR/release-evidence-$release_id.json"

python - "$REPORT_DIR/gitops-adapter-handoff-prep-$release_id.json" <<'PY'
from __future__ import annotations
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
handoff = doc["handoffPrep"]
assert handoff["prepStatus"] == "PREPARED_FOR_HANDOFF", handoff
assert handoff["transitionStatus"] == "PICKUP_ACCEPTED", handoff
assert handoff["preparedArtifactCount"] >= 2, handoff
PY

echo "PASS: gitops adapter handoff prep is generated and validated"
