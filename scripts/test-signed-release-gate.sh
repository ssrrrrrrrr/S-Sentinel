#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-signed-release-gate-test}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

SUPPLY_CHAIN="$TMP_DIR/supply-chain-decision-20260101-000000.json"
RELEASE_EVIDENCE="$TMP_DIR/release-evidence-20260101-000000.json"
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


echo "===== prepare release evidence link ====="
python3 - "$SUPPLY_CHAIN" "$RELEASE_EVIDENCE" <<'PY_PREPARE'
import json
import sys
from pathlib import Path

supply_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

release_evidence = {
    "schemaVersion": "release.evidence.bundle/v1alpha1",
    "generatedBy": "test-signed-release-gate.sh",
    "generatedAt": "2026-01-01T00:00:00Z",
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev",
    "releaseResult": "PASS",
    "policyDecision": "ALLOW",
    "finalAction": "NOOP",
    "artifacts": {},
    "decisionRefs": {}
}
evidence_path.write_text(json.dumps(release_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

supply = json.loads(supply_path.read_text(encoding="utf-8"))
source = supply.setdefault("source", {})
source["releaseEvidence"] = str(evidence_path)
supply_path.write_text(json.dumps(supply, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY_PREPARE

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
echo "===== assert release evidence and EvidenceStore link ====="
DB_FILE="$TMP_DIR/evidence-store.db"
./scripts/evidence-store.py init-db --db "$DB_FILE" >/dev/null
./scripts/evidence-store.py import-dir --db "$DB_FILE" --report-dir "$TMP_DIR" > "$TMP_DIR/evidence-store-import.json"
./scripts/evidence-store.py get-object \
  --db "$DB_FILE" \
  --object-type signedReleaseGate \
  --object-id srg-20260101-000000 \
  --release-id 20260101-000000 \
  > "$TMP_DIR/signed-release-gate-object.json"

python3 - "$RELEASE_EVIDENCE" "$TMP_DIR/evidence-store-import.json" "$TMP_DIR/signed-release-gate-object.json" <<'PY_ASSERT_LINK'
import json
import sys
from pathlib import Path

release_evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
import_result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
obj = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

assert release_evidence["artifacts"]["signedReleaseGate"].endswith("signed-release-gate-20260101-000000.json"), release_evidence
assert release_evidence["decisionRefs"]["signedReleaseGate"]["decision"] == "REQUIRE_HUMAN_APPROVAL", release_evidence
assert release_evidence["signedReleaseGateRef"]["allowed"] is False, release_evidence

assert import_result["byType"]["signedReleaseGate"] == 1, import_result
assert obj["schemaVersion"] == "evidence.store.object/v1alpha1", obj
assert obj["object"]["object_type"] == "signedReleaseGate", obj
assert obj["object"]["object_id"] == "srg-20260101-000000", obj

print("PASS: signed release gate is linked and indexed")
PY_ASSERT_LINK


echo
echo
echo "===== assert ai-release-advisor signed gate integration ====="
grep -q 'SIGNED_RELEASE_GATE_BUILDER' scripts/ai-release-advisor.sh
grep -q 'build-signed-release-gate.sh' scripts/ai-release-advisor.sh
grep -q 'SIGNED_RELEASE_GATE_OUTPUT_DIR' scripts/ai-release-advisor.sh
grep -q 'supply-chain-decision-${DECISION_SUFFIX}' scripts/ai-release-advisor.sh
grep -q 'Running signed release gate builder' scripts/ai-release-advisor.sh
echo "PASS: ai-release-advisor signed release gate integration is wired"

echo "PASS: signed release gate test passed"
