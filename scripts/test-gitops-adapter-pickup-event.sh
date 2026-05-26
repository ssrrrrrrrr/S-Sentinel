#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ssentinel-pickup-event-XXXXXX")"
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
  "releaseId": "$release_id",
  "service": "checkout",
  "env": "prod",
  "namespace": "checkout",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "INVESTIGATE",
  "artifacts": {
    "gitopsAdapterPickup": "$REPORT_DIR/gitops-adapter-pickup-$release_id.json",
    "gitopsAdapterPickupAck": "$REPORT_DIR/gitops-adapter-pickup-ack-$release_id.json",
    "gitopsAdapterHandoffState": "$REPORT_DIR/gitops-adapter-handoff-state-$release_id.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-pickup-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup/v1alpha1",
  "gitopsAdapterPickupId": "gpick-$release_id",
  "pickup": {
    "pickupStatus": "READY_FOR_PICKUP",
    "branchName": "ssentinel/$release_id",
    "requestedOperation": "prepare_pr_handoff",
    "workspaceDir": "$REPORT_DIR/workspace",
    "nextCheckpoint": "await_pickup_ack",
    "nextActor": "service_owner_or_release_operator"
  },
  "guardrails": {}
}
JSON

cat > "$REPORT_DIR/gitops-adapter-pickup-ack-$release_id.json" <<JSON
{
  "schemaVersion": "gitops.adapter.pickup.ack/v1alpha1",
  "gitopsAdapterPickupAckId": "gack-$release_id",
  "acknowledgement": {
    "ackStatus": "WAITING_FOR_ACK",
    "pickupStatus": "READY_FOR_PICKUP",
    "branchName": "ssentinel/$release_id",
    "requestedOperation": "prepare_pr_handoff",
    "workspaceDir": "$REPORT_DIR/workspace",
    "nextCheckpoint": "acknowledge_pickup_workspace",
    "assignedActor": "service_owner_or_release_operator"
  },
  "guardrails": {}
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
    "nextActor": "service_owner_or_release_operator"
  },
  "guardrails": {}
}
JSON

RELEASE_REPORT_DIR="$REPORT_DIR" "$ROOT_DIR/scripts/build-gitops-adapter-pickup-event.sh" "$REPORT_DIR/release-evidence-$release_id.json" >/dev/null

python "$ROOT_DIR/scripts/validate-release-contracts.py" \
  "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json" \
  "$REPORT_DIR/release-evidence-$release_id.json"

python - "$REPORT_DIR/gitops-adapter-pickup-event-$release_id.json" <<'PY'
from __future__ import annotations
import json
import sys
from pathlib import Path

doc = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
event = doc["pickupEvent"]
assert event["eventStatus"] == "WAITING_FOR_EVENT", event
assert event["expectedEvent"] == "ACCEPT_OR_RETURN_PICKUP", event
assert event["allowedEvents"] == ["ACCEPT_PICKUP", "RETURN_PICKUP"], event
PY

echo "PASS: gitops adapter pickup event is generated and validated"
