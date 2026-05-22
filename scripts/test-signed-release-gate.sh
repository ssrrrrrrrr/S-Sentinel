#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-signed-release-gate-test}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

SUPPLY_CHAIN="$TMP_DIR/supply-chain-decision-20260101-000000.json"
GATE="$TMP_DIR/signed-release-gate-20260101-000000.json"

cat > "$SUPPLY_CHAIN" <<'JSON'
{
  "schemaVersion": "supply.chain.decision/v1alpha1",
  "supplyChainDecisionId": "sc-20260101-000000",
  "generatedBy": "test-signed-release-gate.sh",
  "generatedAt": "2026-01-01T00:00:00Z",
  "mode": "read_only_supply_chain_check",
  "release": {
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "version": "v-test",
    "commit": "abc123"
  },
  "image": {
    "image": "registry.local/demo-app@sha256:111",
    "imageTag": null,
    "imageDigest": "sha256:111",
    "usesDigestReference": true,
    "usesMutableTag": false
  },
  "gitops": {},
  "attestations": {
    "sbom": {
      "ref": null
    },
    "provenance": {
      "ref": null
    },
    "cosign": {
      "verified": false
    },
    "slsa": {
      "level": null
    }
  },
  "checks": [],
  "decision": {
    "decision": "ALLOW",
    "requiresHumanApproval": false,
    "allowed": true,
    "blockingReasons": [],
    "warningReasons": []
  },
  "risk": {
    "riskLevel": "low",
    "riskScore": 0
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false,
    "doesNotModifyKubernetes": true,
    "doesNotModifyGitOps": true,
    "doesNotBuildImages": true,
    "doesNotPushImages": true,
    "doesNotCommitOrPush": true
  }
}
JSON

echo "===== build signed release gate ====="
SIGNED_RELEASE_GATE_OUTPUT_DIR="$TMP_DIR" ./scripts/build-signed-release-gate.sh "$SUPPLY_CHAIN"

echo
echo "===== assert signed release gate ====="
python3 - "$GATE" "$TMP_DIR/signed-release-gate-latest.json" <<'PY'
import json
import sys
from pathlib import Path

gate = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
latest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert gate["schemaVersion"] == "signed.release.gate/v1alpha1", gate
assert gate["signedReleaseGateId"] == "srg-20260101-000000", gate
assert gate["mode"] == "read_only_signed_release_gate", gate
assert gate["decision"]["decision"] == "REQUIRE_HUMAN_APPROVAL", gate
assert gate["decision"]["allowed"] is False, gate
assert gate["decision"]["requiresHumanApproval"] is True, gate
assert gate["image"]["imageDigest"] == "sha256:111", gate
assert gate["image"]["usesDigestReference"] is True, gate
assert gate["attestations"]["cosign"]["verified"] is False, gate
assert gate["guardrails"]["readOnly"] is True, gate
assert gate["guardrails"]["willExecute"] is False, gate
assert gate["guardrails"]["doesNotSignImages"] is True, gate
assert latest["signedReleaseGateId"] == gate["signedReleaseGateId"], latest

check_ids = {item["checkId"] for item in gate["checks"]}
assert "image_digest_present" in check_ids, gate
assert "cosign_signature_verified" in check_ids, gate
assert "sbom_available" in check_ids, gate
assert "provenance_available" in check_ids, gate

print("PASS: signed release gate contract is valid")
PY

echo
echo "PASS: signed release gate test passed"
