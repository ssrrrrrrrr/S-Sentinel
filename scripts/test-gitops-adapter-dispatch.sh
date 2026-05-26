#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.tmp/gitops-adapter-dispatch-test"
REPORT_DIR="${TMP_DIR}/reports"

rm -rf "$TMP_DIR"
mkdir -p "$REPORT_DIR"

PAYLOAD_DIR="${TMP_DIR}/payload"
mkdir -p "$PAYLOAD_DIR"

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
    "pullRequest": {
      "title": "Promote demo"
    }
  }
}
JSON

cat >"$REPORT_DIR/gitops-adapter-delivery-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.delivery/v1alpha1",
  "gitopsAdapterDeliveryId": "gd-demo",
  "delivery": {
    "deliveryStatus": "WORKSPACE_READY",
    "branchName": "release/demo",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "${PAYLOAD_DIR//\\/\\\\}"
  }
}
JSON

cat >"$PAYLOAD_DIR/payload-manifest.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.payload.manifest/v1alpha1"
}
JSON

cat >"$PAYLOAD_DIR/commit-payload.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.commit.payload/v1alpha1",
  "pullRequestTitle": "Promote demo"
}
JSON

cat >"$REPORT_DIR/gitops-adapter-payload-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.payload/v1alpha1",
  "gitopsAdapterPayloadId": "gpay-demo",
  "release": {
    "releaseId": "demo",
    "service": "demo-app",
    "env": "staging",
    "namespace": "demo",
    "policyDecision": "allow",
    "finalAction": "promote"
  },
  "payload": {
    "payloadStatus": "PAYLOAD_READY",
    "branchName": "release/demo",
    "requestedOperation": "prepare_review_handoff_delivery",
    "workspaceDir": "${PAYLOAD_DIR//\\/\\\\}",
    "patchEntryCount": 1,
    "workspaceArtifactCount": 1,
    "payloadManifest": {
      "path": "${PAYLOAD_DIR//\\/\\\\}/payload-manifest.json",
      "commitPayloadPath": "${PAYLOAD_DIR//\\/\\\\}/commit-payload.json"
    },
    "warnings": []
  }
}
JSON

python - <<'PY'
from pathlib import Path
import json
path = Path(".tmp/gitops-adapter-dispatch-test/reports/release-evidence-demo.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["artifacts"] = {
    "gitopsAdapterPayload": str(Path(".tmp/gitops-adapter-dispatch-test/reports/gitops-adapter-payload-demo.json").resolve()),
    "gitopsAdapterDelivery": str(Path(".tmp/gitops-adapter-dispatch-test/reports/gitops-adapter-delivery-demo.json").resolve()),
    "gitopsPRBundle": str(Path(".tmp/gitops-adapter-dispatch-test/reports/gitops-pr-bundle-demo.json").resolve())
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

bash "$ROOT_DIR/scripts/build-gitops-adapter-dispatch.sh" "$REPORT_DIR/release-evidence-demo.json" >/dev/null
python "$ROOT_DIR/scripts/validate-release-contracts.py" "$REPORT_DIR/gitops-adapter-dispatch-demo.json" >/dev/null

echo "gitops adapter dispatch test passed"
