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

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-gitops-adapter-delivery-test}"
REPORT_DIR="$TMP_DIR/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

RELEASE_ID="20260101-141414"
WORKSPACE_DIR="$REPORT_DIR/gitops-handoff-$RELEASE_ID"
mkdir -p "$WORKSPACE_DIR"

cat > "$WORKSPACE_DIR/manifest.json" <<'JSON'
{"kind":"handoff-manifest"}
JSON
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
  "generatedBy": "test-gitops-adapter-delivery.sh",
  "releaseId": "$RELEASE_ID",
  "generatedAt": "2026-01-01T14:14:14Z",
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
    "gitopsHandoffBundle": "gitops-handoff-bundle-$RELEASE_ID.json",
    "gitopsAdapterRequest": "gitops-adapter-request-$RELEASE_ID.json",
    "gitopsAdapterResult": "gitops-adapter-result-$RELEASE_ID.json"
  },
  "decisionRefs": {}
}
JSON

cat > "$REPORT_DIR/gitops-handoff-bundle-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.handoff.bundle/v1alpha1",
  "gitopsHandoffBundleId": "hb-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-delivery.sh",
  "generatedAt": "2026-01-01T14:14:15Z",
  "mode": "review_only_gitops_handoff_bundle",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "handoff": {
    "handoffStatus": "WAITING_APPROVAL",
    "bundleDir": "$WORKSPACE_DIR",
    "branchName": "ssentinel/$RELEASE_ID",
    "commitMessage": "chore: stop promotion",
    "pullRequestTitle": "Stop promotion",
    "materializedFiles": [
      {"fileId": "manifest", "path": "manifest.json", "contentType": "application/json", "description": "manifest"},
      {"fileId": "patches", "path": "patch-entries.json", "contentType": "application/json", "description": "patch entries"},
      {"fileId": "pr-body", "path": "pull-request.md", "contentType": "text/markdown", "description": "pr body"},
      {"fileId": "checklist", "path": "handoff-checklist.md", "contentType": "text/markdown", "description": "checklist"}
    ],
    "patchEntryCount": 1,
    "handoffChecklistCount": 1
  },
  "guardrails": {
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$REPORT_DIR/gitops-adapter-request-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "gitops.adapter.request/v1alpha1",
  "gitopsAdapterRequestId": "ga-$RELEASE_ID",
  "generatedBy": "test-gitops-adapter-delivery.sh",
  "generatedAt": "2026-01-01T14:14:16Z",
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
  "inputs": {
    "releaseEvidence": "release-evidence-$RELEASE_ID.json",
    "gitopsPatchProposal": null,
    "gitopsPRBundle": null,
    "gitopsHandoffBundle": "gitops-handoff-bundle-$RELEASE_ID.json"
  },
  "request": {
    "requestStatus": "WAITING_APPROVAL",
    "adapterType": "gitops-handoff-local",
    "requestedOperation": "prepare_review_handoff_delivery",
    "bundleDir": "$WORKSPACE_DIR",
    "delivery": {
      "branchName": "ssentinel/$RELEASE_ID",
      "commitMessage": "chore: stop promotion",
      "pullRequestTitle": "Stop promotion",
      "localOnly": true,
      "doesNotCallExternalGitProvider": true
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
  "generatedBy": "test-gitops-adapter-delivery.sh",
  "generatedAt": "2026-01-01T14:14:17Z",
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
  "inputs": {
    "releaseEvidence": "release-evidence-$RELEASE_ID.json",
    "gitopsAdapterRequest": "gitops-adapter-request-$RELEASE_ID.json",
    "gitopsHandoffBundle": "gitops-handoff-bundle-$RELEASE_ID.json",
    "gitopsPRBundle": null
  },
  "adapter": {
    "adapter": "gitops-handoff-local",
    "adapterType": "gitops-handoff-local",
    "deliveryMode": "local_only_delivery_receipt",
    "readOnly": true,
    "dryRunOnly": true,
    "willExecute": false,
    "doesNotCallExternalGitProvider": true,
    "emitsDeliveryReceipt": true
  },
  "delivery": {
    "deliveryStatus": "WAITING_APPROVAL",
    "requestedOperation": "prepare_review_handoff_delivery",
    "summary": "Local GitOps adapter recorded a receipt.",
    "receipt": {
      "bundleDir": "$WORKSPACE_DIR",
      "branchName": "ssentinel/$RELEASE_ID",
      "commitMessage": "chore: stop promotion",
      "pullRequestTitle": "Stop promotion",
      "localOnly": true,
      "receivedAt": "2026-01-01T14:14:17Z",
      "processedAt": "2026-01-01T14:14:17Z"
    },
    "outputFiles": [
      {"fileId": "manifest", "path": "manifest.json", "contentType": "application/json", "description": "manifest"},
      {"fileId": "patches", "path": "patch-entries.json", "contentType": "application/json", "description": "patch entries"},
      {"fileId": "pr-body", "path": "pull-request.md", "contentType": "text/markdown", "description": "pr body"},
      {"fileId": "checklist", "path": "handoff-checklist.md", "contentType": "text/markdown", "description": "checklist"}
    ],
    "warnings": [],
    "failureReason": null
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

echo "===== build gitops adapter delivery ====="
./scripts/build-gitops-adapter-delivery.sh "$REPORT_DIR/release-evidence-$RELEASE_ID.json" > "$TMP_DIR/delivery.log"
cat "$TMP_DIR/delivery.log"

echo
echo "===== assert gitops adapter delivery ====="
"$PYTHON_BIN" - "$REPORT_DIR/release-evidence-$RELEASE_ID.json" "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
delivery = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert delivery["schemaVersion"] == "gitops.adapter.delivery/v1alpha1"
assert delivery["gitopsAdapterDeliveryId"] == "gad-20260101-141414"
assert delivery["delivery"]["deliveryStatus"] == "WAITING_APPROVAL"
assert len(delivery["delivery"]["copiedFiles"]) == 4
assert Path(delivery["delivery"]["manifestFile"]).exists()
assert Path(delivery["delivery"]["pickupInstructionsFile"]).exists()
assert evidence["gitopsAdapterDeliveryId"] == "gad-20260101-141414"
assert evidence["decisionRefs"]["gitopsAdapterDelivery"]["copiedFileCount"] == 4

print("PASS: gitops adapter delivery generated and linked")
PY

echo
echo "===== validate contracts ====="
"$PYTHON_BIN" ./scripts/validate-release-contracts.py \
  "$REPORT_DIR/release-evidence-$RELEASE_ID.json" \
  "$REPORT_DIR/gitops-adapter-delivery-$RELEASE_ID.json"

echo
echo "PASS: gitops adapter delivery test passed"
