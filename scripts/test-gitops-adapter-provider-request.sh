#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.tmp/gitops-adapter-provider-request-test"
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

cat >"$PAYLOAD_DIR/payload-manifest.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.payload.manifest/v1alpha1"
}
JSON

cat >"$PAYLOAD_DIR/commit-payload.json" <<'JSON'
{
  "schemaVersion": "gitops.adapter.commit.payload/v1alpha1",
  "commitMessage": "promote demo",
  "pullRequestTitle": "Promote demo"
}
JSON

cat >"$REPORT_DIR/gitops-adapter-payload-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.payload/v1alpha1",
  "gitopsAdapterPayloadId": "gpay-demo",
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
    }
  }
}
JSON

cat >"$REPORT_DIR/gitops-adapter-dispatch-demo.json" <<JSON
{
  "schemaVersion": "gitops.adapter.dispatch/v1alpha1",
  "gitopsAdapterDispatchId": "gdisp-demo",
  "release": {
    "releaseId": "demo",
    "service": "demo-app",
    "env": "staging",
    "namespace": "demo",
    "policyDecision": "allow",
    "finalAction": "promote"
  },
  "dispatch": {
    "dispatchStatus": "STUB_DISPATCHED",
    "branchName": "release/demo",
    "requestedOperation": "prepare_review_handoff_delivery",
    "payloadManifestPath": "${PAYLOAD_DIR//\\/\\\\}/payload-manifest.json",
    "commitPayloadPath": "${PAYLOAD_DIR//\\/\\\\}/commit-payload.json",
    "providerRequestPath": "${PAYLOAD_DIR//\\/\\\\}/provider-request.json",
    "patchEntryCount": 1,
    "workspaceArtifactCount": 1,
    "warnings": []
  }
}
JSON

python - <<'PY'
from pathlib import Path
import json
path = Path(".tmp/gitops-adapter-provider-request-test/reports/release-evidence-demo.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["artifacts"] = {
    "gitopsAdapterDispatch": str(Path(".tmp/gitops-adapter-provider-request-test/reports/gitops-adapter-dispatch-demo.json").resolve()),
    "gitopsAdapterPayload": str(Path(".tmp/gitops-adapter-provider-request-test/reports/gitops-adapter-payload-demo.json").resolve()),
    "gitopsPRBundle": str(Path(".tmp/gitops-adapter-provider-request-test/reports/gitops-pr-bundle-demo.json").resolve())
}
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

bash "$ROOT_DIR/scripts/build-gitops-adapter-provider-request.sh" "$REPORT_DIR/release-evidence-demo.json" >/dev/null
python "$ROOT_DIR/scripts/validate-release-contracts.py" "$REPORT_DIR/gitops-adapter-provider-request-demo.json" >/dev/null

echo "gitops adapter provider request test passed"
