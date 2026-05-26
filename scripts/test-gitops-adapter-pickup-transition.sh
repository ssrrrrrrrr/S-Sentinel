#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssentinel-pickup-transition-XXXXXX")"
REPORT_DIR="$TMP_DIR/reports"
mkdir -p "$REPORT_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

release_id="20260526-120000"

cat > "$REPORT_DIR/release-evidence-$release_id.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "fixture",
  "generatedAt": "2026-05-26T12:00:00Z",
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
    "releaseContext": "docs/release-reports/release-context-20260526-120000.json",
    "aiDecision": "docs/release-reports/ai-decision-20260526-120000.json",
    "policyDecision": "docs/release-reports/policy-decision-20260526-120000.json",
    "releaseSummary": null,
    "actionPlan": null,
    "gitopsAdapterPickupEvent": "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json",
    "gitopsAdapterHandoffState": "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup.event/v1alpha1",
  "gitopsAdapterPickupEventId": "gpe-$release_id",
  "generatedBy": "fixture",
  "generatedAt": "2026-05-26T12:00:00Z",
  "mode": "local_gitops_adapter_pickup_event",
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
    "gitopsAdapterPickup": null,
    "gitopsAdapterPickupAck": null,
    "gitopsAdapterHandoffState": "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json"
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
      "generatedAt": "2026-05-26T12:00:00Z",
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
      "generatedAt": "2026-05-26T12:00:00Z",
      "localOnly": true
    }
  },
  "guardrails": {
    "willExecute": false
  }
}
JSON

GITOPS_ADAPTER_PICKUP_RESPONSE="ACCEPT_PICKUP" \
RELEASE_REPORT_DIR="$REPORT_DIR" \
  "$ROOT_DIR/scripts/build-gitops-adapter-pickup-transition.sh" "$REPORT_DIR/release-evidence-$release_id.json" >/dev/null

python "$ROOT_DIR/scripts/validate-release-contracts.py" \
  "$REPORT_DIR/gitops-adapter-pickup-transition-$release_id.json" \
  "$REPORT_DIR/release-evidence-$release_id.json"

python - "$REPORT_DIR/gitops-adapter-pickup-transition-$release_id.json" <<'PY'
from __future__ import annotations
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
transition = doc["pickupTransition"]
assert transition["transitionStatus"] == "PICKUP_ACCEPTED", transition
assert transition["selectedEvent"] == "ACCEPT_PICKUP", transition
assert transition["resultingStateStatus"] == "PICKUP_ACCEPTED", transition
PY

echo "PASS: gitops adapter pickup transition is generated and validated"
