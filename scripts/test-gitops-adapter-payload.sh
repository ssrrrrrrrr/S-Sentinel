#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.tmp/gitops-adapter-payload-test"
REPORT_DIR="${TMP_DIR}/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

cat >"$REPORT_DIR/release-evidence-demo.json" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "releaseId": "demo",
  "service": "demo-app",
  "env": "staging",
  "namespace": "demo",
  "policyDecision": "allow",
  "finalAction": "promote",
  "environment": {
    "env": "staging",
    "namespace": "demo"
  },
  "artifacts": {}
}
JSON

cat >"$REPORT_DIR/gitops-pr-bundle-demo.json" <<'JSON'
{
  "schemaVersion": "gitops.pr.bundle/v1alpha1",
  "gitopsPRBundleId": "gb-demo",
  "bundle": {
    "patchEntries": [
      {
        "path": "kustomization.yaml"
      }
    ],
    "pullRequest": {
      "title": "Promote demo"
    }
  }
}
JSON

mkdir -p "$TMP_DIR/handoff"
cat >"$REPORT_DIR/gitops-handoff-bundle-demo.json" <<JSON
{
  "schemaVersion": "gitops.handoff.bundle/v1alpha1",
  "gitopsHandoffBundleId": "gh-demo",
  "handoff": {
    "bundleDir": "${TMP_DIR//\\/\\\\}/handoff",
    "branchName": "release/demo",
    "commitMessage": "promote demo",
    "pullRequestTitle": "Promote demo",
    "materializedFiles": [
      {
        "fileId": "pull-request",
        "path": "${TMP_DIR//\\/\\\\}/handoff/pull-request.md",
        "contentType": "text/markdown",
        "description": "PR body"
      }
    ],
    "handoffChecklist": [
      "review"
    ]
  }
}
JSON
printf '# demo\n' >"$TMP_DIR/handoff/pull-request.md"

mkdir -p "$TMP_DIR/workspace/delivery-files"
printf '# workspace\n' >"$TMP_DIR/workspace/delivery-files/pull-request.md"

cat >"$REPORT_DIR/gitops-adapter-delivery-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gd-demo",
  "delivery": {
    "deliveryStatus": "WORKSPACE_READY",
    "branchName": "release/demo",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "${TMP_DIR//\\/\\\\}/workspace",
    "copiedFiles": [
      {
        "fileId": "pull-request",
        "sourcePath": "${TMP_DIR//\\/\\\\}/handoff/pull-request.md",
        "workspacePath": "${TMP_DIR//\\/\\\\}/workspace/delivery-files/pull-request.md",
        "contentType": "text/markdown",
        "description": "PR body"
      }
    ]
  }
}
JSON

cat >"$REPORT_DIR/gitops-adapter-handoff-progress-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.handoff.progress/v1alpha1",
  "gitopsAdapterHandoffProgressId": "ghpr-demo",
  "release": {
    "releaseId": "demo",
    "service": "demo-app",
    "env": "staging",
    "namespace": "demo",
    "policyDecision": "allow",
    "finalAction": "promote"
  },
  "handoffProgress": {
    "progressStatus": "HANDOFF_COMPLETED",
    "prepStatus": "PREPARED_FOR_HANDOFF",
    "transitionStatus": "PICKUP_ACCEPTED",
    "eventStatus": "WAITING_FOR_EVENT",
    "handoffStateStatus": "READY_FOR_ACKNOWLEDGEMENT",
    "pickupStatus": "READY_FOR_PICKUP",
    "ackStatus": "WAITING_FOR_ACK",
    "branchName": "release/demo",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "${TMP_DIR//\\/\\\\}/workspace",
    "warnings": []
  }
}
JSON

python - <<'PY'
from pathlib import Path
import json
path = Path(".tmp/gitops-adapter-payload-test/reports/release-evidence-demo.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["artifacts"] = {
    "gitopsPRBundle": str(Path(".tmp/gitops-adapter-payload-test/reports/gitops-pr-bundle-demo.json").resolve()),
    "gitopsHandoffBundle": str(Path(".tmp/gitops-adapter-payload-test/reports/gitops-handoff-bundle-demo.json").resolve()),
    "gitopsAdapterDelivery": str(Path(".tmp/gitops-adapter-payload-test/reports/gitops-adapter-delivery-demo.json").resolve()),
    "gitopsAdapterHandoffProgress": str(Path(".tmp/gitops-adapter-payload-test/reports/gitops-adapter-handoff-progress-demo.json").resolve())
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

bash "$ROOT_DIR/scripts/build-gitops-adapter-payload.sh" "$REPORT_DIR/release-evidence-demo.json" >/dev/null
python "$ROOT_DIR/scripts/validate-release-contracts.py" "$REPORT_DIR/gitops-adapter-payload-demo.json" >/dev/null

echo "gitops adapter payload test passed"
