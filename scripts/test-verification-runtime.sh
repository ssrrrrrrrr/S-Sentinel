#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SUPPLY_CHAIN="$TMP_DIR/supply-chain-decision-20260101-000000.json"
INPUT_DERIVED="$TMP_DIR/verification-input-derived.json"
EXTERNAL_PREVIEW="$TMP_DIR/verification-external-command.json"
ADMISSION_PLACEHOLDER="$TMP_DIR/verification-admission.json"

cat > "$SUPPLY_CHAIN" <<'JSON'
{
  "schemaVersion": "supply.chain.decision/v1alpha1",
  "supplyChainDecisionId": "sc-20260101-000000",
  "release": {
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "image": {
    "image": "registry.local/demo-app@sha256:111",
    "imageDigest": "sha256:111",
    "usesDigestReference": true,
    "usesMutableTag": false
  },
  "attestations": {
    "sbom": {
      "ref": "sbom.json"
    },
    "provenance": {
      "ref": "provenance.json"
    },
    "cosign": {
      "verified": false
    },
    "slsa": {
      "level": "unknown"
    }
  }
}
JSON

echo "===== verification runtime syntax ====="
"$PYTHON_BIN" -m py_compile scripts/verification-runtime.py
rm -rf scripts/__pycache__

echo "===== input-derived runtime ====="
scripts/verification-runtime.py input-derived \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --output "$INPUT_DERIVED"

echo "===== external-command-preview runtime ====="
scripts/verification-runtime.py external-command-preview \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --cosign-bin /tmp/ssentinel-missing-cosign \
  --output "$EXTERNAL_PREVIEW"

echo "===== admission-placeholder runtime ====="
scripts/verification-runtime.py admission-placeholder \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --output "$ADMISSION_PLACEHOLDER"

echo "===== assert verification runtime contract ====="
"$PYTHON_BIN" - "$INPUT_DERIVED" "$EXTERNAL_PREVIEW" "$ADMISSION_PLACEHOLDER" <<'PY'
import json
import sys
from pathlib import Path

input_derived = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
external = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
admission = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

for item in [input_derived, external, admission]:
    assert item["schemaVersion"] == "signed.release.gate.verification/v1alpha1", item
    assert item["command"] is None, item
    assert item["exitCode"] is None, item
    assert item["subject"]["image"] == "registry.local/demo-app@sha256:111", item
    assert item["subject"]["imageDigest"] == "sha256:111", item
    assert item["results"]["imageDigestPresent"] is True, item
    assert item["results"]["usesDigestReference"] is True, item
    assert item["results"]["signatureVerified"] is False, item
    assert item["results"]["sbomPresent"] is True, item
    assert item["results"]["provenancePresent"] is True, item
    assert item["results"]["slsaLevelPresent"] is True, item
    assert item["guardrails"]["readOnly"] is True, item
    assert item["guardrails"]["willExecute"] is False, item
    assert item["guardrails"]["canRunExternalVerification"] is False, item
    assert item["guardrails"]["doesNotRunExternalCommands"] is True, item
    assert item["guardrails"]["doesNotVerifyExternalServices"] is True, item

assert input_derived["mode"] == "input_derived", input_derived
assert input_derived["tool"] == "cosign", input_derived
assert input_derived["commandPreview"] == ["cosign", "verify", "registry.local/demo-app@sha256:111"], input_derived

assert external["mode"] == "external_command", external
assert external["tool"] == "cosign", external
assert external["toolBinary"] == "/tmp/ssentinel-missing-cosign", external
assert external["toolAvailable"] is False, external
assert external["commandPreview"] == ["/tmp/ssentinel-missing-cosign", "verify", "registry.local/demo-app@sha256:111"], external

assert admission["mode"] == "admission", admission
assert admission["tool"] == "admission", admission
assert admission["toolBinary"] is None, admission
assert admission["toolAvailable"] is False, admission
assert admission["commandPreview"] is None, admission

print("PASS: verification runtime contract is valid")
PY

echo "===== signed release gate compatibility regression ====="
scripts/test-signed-release-gate.sh

echo "PASS: verification runtime test passed"
