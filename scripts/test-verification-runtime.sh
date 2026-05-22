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
EXTERNAL_ENABLED="$TMP_DIR/verification-external-command-enabled.json"
ADMISSION_PLACEHOLDER="$TMP_DIR/verification-admission.json"
FAKE_COSIGN="$TMP_DIR/fake-cosign"

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

cat > "$FAKE_COSIGN" <<'SH_FAKE'
#!/usr/bin/env bash
echo "fake cosign invoked: $*"
exit 0
SH_FAKE
chmod +x "$FAKE_COSIGN"

echo "===== verification runtime syntax ====="
"$PYTHON_BIN" -m py_compile scripts/verification-runtime.py
rm -rf scripts/__pycache__

echo "===== input-derived runtime ====="
scripts/verification-runtime.py input-derived \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --output "$INPUT_DERIVED"

echo "===== external-command-preview runtime default disabled ====="
scripts/verification-runtime.py external-command-preview \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --cosign-bin /tmp/ssentinel-missing-cosign \
  --output "$EXTERNAL_PREVIEW"

echo "===== external-command runtime explicitly enabled with fake verifier ====="
S_SENTINEL_VERIFICATION_ALLOW_EXTERNAL_COMMAND=1 \
scripts/verification-runtime.py external-command-preview \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --cosign-bin "$FAKE_COSIGN" \
  --output "$EXTERNAL_ENABLED"

echo "===== admission-placeholder runtime ====="
scripts/verification-runtime.py admission-placeholder \
  --supply-chain-decision "$SUPPLY_CHAIN" \
  --output "$ADMISSION_PLACEHOLDER"

echo "===== assert verification runtime contract ====="
"$PYTHON_BIN" - "$INPUT_DERIVED" "$EXTERNAL_PREVIEW" "$EXTERNAL_ENABLED" "$ADMISSION_PLACEHOLDER" "$FAKE_COSIGN" <<'PY'
import json
import sys
from pathlib import Path

input_derived = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
external = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
external_enabled = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
admission = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
fake_cosign = sys.argv[5]

for item in [input_derived, external, external_enabled, admission]:
    assert item["schemaVersion"] == "signed.release.gate.verification/v1alpha1", item
    assert item["subject"]["image"] == "registry.local/demo-app@sha256:111", item
    assert item["subject"]["imageDigest"] == "sha256:111", item
    assert item["results"]["imageDigestPresent"] is True, item
    assert item["results"]["usesDigestReference"] is True, item
    assert item["results"]["signatureVerified"] is False, item
    assert item["results"]["sbomPresent"] is True, item
    assert item["results"]["provenancePresent"] is True, item
    assert item["results"]["slsaLevelPresent"] is True, item
    assert item["guardrails"]["readOnly"] is True, item

assert input_derived["mode"] == "input_derived", input_derived
assert input_derived["tool"] == "cosign", input_derived
assert input_derived["command"] is None, input_derived
assert input_derived["exitCode"] is None, input_derived
assert input_derived["commandPreview"] == ["cosign", "verify", "registry.local/demo-app@sha256:111"], input_derived
assert input_derived["results"]["externalVerificationRequested"] is False, input_derived
assert input_derived["results"]["externalVerificationExecuted"] is False, input_derived
assert input_derived["guardrails"]["willExecute"] is False, input_derived
assert input_derived["guardrails"]["canRunExternalVerification"] is False, input_derived
assert input_derived["guardrails"]["doesNotRunExternalCommands"] is True, input_derived

assert external["mode"] == "external_command", external
assert external["tool"] == "cosign", external
assert external["toolBinary"] == "/tmp/ssentinel-missing-cosign", external
assert external["toolAvailable"] is False, external
assert external["command"] is None, external
assert external["exitCode"] is None, external
assert external["commandPreview"] == ["/tmp/ssentinel-missing-cosign", "verify", "registry.local/demo-app@sha256:111"], external
assert external["results"]["externalVerificationRequested"] is True, external
assert external["results"]["externalVerificationAllowed"] is False, external
assert external["results"]["externalVerificationExecuted"] is False, external
assert external["results"]["externalVerificationSucceeded"] is None, external
assert external["results"]["externalVerificationSkippedReason"] == "external_command_not_enabled", external
assert external["guardrails"]["willExecute"] is False, external
assert external["guardrails"]["canRunExternalVerification"] is False, external
assert external["guardrails"]["doesNotRunExternalCommands"] is True, external
assert external["guardrails"]["doesNotVerifyExternalServices"] is True, external

assert external_enabled["mode"] == "external_command", external_enabled
assert external_enabled["tool"] == "cosign", external_enabled
assert external_enabled["toolBinary"] == fake_cosign, external_enabled
assert external_enabled["toolAvailable"] is True, external_enabled
assert external_enabled["command"] == [fake_cosign, "verify", "registry.local/demo-app@sha256:111"], external_enabled
assert external_enabled["exitCode"] == 0, external_enabled
assert "fake cosign invoked: verify registry.local/demo-app@sha256:111" in external_enabled["stdout"], external_enabled
assert external_enabled["results"]["externalVerificationRequested"] is True, external_enabled
assert external_enabled["results"]["externalVerificationAllowed"] is True, external_enabled
assert external_enabled["results"]["externalVerificationExecuted"] is True, external_enabled
assert external_enabled["results"]["externalVerificationSucceeded"] is True, external_enabled
assert external_enabled["results"]["externalVerificationSkippedReason"] is None, external_enabled
assert external_enabled["guardrails"]["willExecute"] is True, external_enabled
assert external_enabled["guardrails"]["canRunExternalVerification"] is True, external_enabled
assert external_enabled["guardrails"]["doesNotRunExternalCommands"] is False, external_enabled
assert external_enabled["guardrails"]["doesNotVerifyExternalServices"] is False, external_enabled

assert admission["mode"] == "admission", admission
assert admission["tool"] == "admission", admission
assert admission["toolBinary"] is None, admission
assert admission["toolAvailable"] is False, admission
assert admission["command"] is None, admission
assert admission["exitCode"] is None, admission
assert admission["commandPreview"] is None, admission
assert admission["results"]["externalVerificationRequested"] is False, admission
assert admission["guardrails"]["doesNotRunExternalCommands"] is True, admission

print("PASS: verification runtime contract is valid")
PY

echo "===== signed release gate compatibility regression ====="
scripts/test-signed-release-gate.sh

echo "PASS: verification runtime test passed"
