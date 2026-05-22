#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-signed-release-gate.sh [latest|SUPPLY_CHAIN_DECISION_JSON]

Environment:
  RELEASE_REPORT_DIR                 Optional report directory.
  SIGNED_RELEASE_GATE_OUTPUT_DIR     Optional output directory.
  SIGNED_RELEASE_GATE_OUTPUT_FILE    Optional exact output file.

Behavior:
  - Reads supply-chain-decision-*.json.
  - Generates signed-release-gate-*.json and signed-release-gate-latest.json.
  - Performs read-only signed release gate checks.
  - Does not sign images, verify external services, modify Kubernetes, GitOps, images, commits, or pushes.
USAGE
}

if [ "${INPUT_FILE:-}" = "-h" ] || [ "${INPUT_FILE:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ "$INPUT_FILE" = "latest" ] || [ -z "$INPUT_FILE" ]; then
  INPUT_FILE="$(ls -t "$REPORT_DIR"/supply-chain-decision-*.json 2>/dev/null | grep -v 'supply-chain-decision-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: supply chain decision file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#supply-chain-decision-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_DIR="${SIGNED_RELEASE_GATE_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="${SIGNED_RELEASE_GATE_OUTPUT_FILE:-$OUTPUT_DIR/signed-release-gate-$SUFFIX}"
LATEST_JSON="$OUTPUT_DIR/signed-release-gate-latest.json"

python3 - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

input_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
latest_json = Path(sys.argv[3])

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}

def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}

def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]

def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None

def bool_value(value: Any) -> bool:
    return bool(value) if value is not None else False

def add_check(checks: list[dict[str, Any]], check_id: str, status: str, severity: str, message: str, evidence: dict[str, Any] | None = None) -> None:
    checks.append({
        "checkId": check_id,
        "status": status,
        "severity": severity,
        "message": message,
        "evidence": evidence or {},
    })

def score_for(status: str, severity: str) -> int:
    if status == "PASS":
        return 0
    if status == "FAIL":
        return {"critical": 60, "high": 40, "medium": 20, "low": 10}.get(severity, 20)
    return {"critical": 30, "high": 20, "medium": 10, "low": 5}.get(severity, 5)

def risk_level(score: int) -> str:
    if score >= 70:
        return "critical"
    if score >= 40:
        return "high"
    if score >= 15:
        return "medium"
    return "low"

supply = load_json(input_path)
release = as_dict(supply.get("release"))
image = as_dict(supply.get("image"))
decision = as_dict(supply.get("decision"))

attestations = as_dict(supply.get("attestations"))
sbom = as_dict(attestations.get("sbom"))
provenance = as_dict(attestations.get("provenance"))
cosign = as_dict(attestations.get("cosign"))
slsa = as_dict(attestations.get("slsa"))

release_id = nullable_string(release.get("releaseId")) or input_path.stem
gate_id = "srg-" + release_id

image_ref = nullable_string(image.get("image"))
image_digest = nullable_string(image.get("imageDigest"))
uses_mutable_tag = bool_value(image.get("usesMutableTag"))
uses_digest_reference = bool_value(image.get("usesDigestReference"))

sbom_ref = nullable_string(sbom.get("ref") or sbom.get("path"))
provenance_ref = nullable_string(provenance.get("ref") or provenance.get("path"))
cosign_verified = bool_value(cosign.get("verified"))
slsa_level = nullable_string(slsa.get("level") or slsa.get("slsaLevel"))

checks: list[dict[str, Any]] = []

if image_digest:
    add_check(checks, "image_digest_present", "PASS", "none", "Image digest is present", {"imageDigest": image_digest})
else:
    add_check(checks, "image_digest_present", "WARN", "high", "Image digest is missing", {"image": image_ref})

if uses_mutable_tag:
    add_check(checks, "mutable_tag_blocked", "FAIL", "critical", "Mutable image tag is not acceptable for signed release gate", {"image": image_ref})
else:
    add_check(checks, "mutable_tag_blocked", "PASS", "none", "Image tag is not marked as mutable", {"image": image_ref})

if uses_digest_reference:
    add_check(checks, "digest_reference_used", "PASS", "none", "Image reference uses digest form", {"image": image_ref})
else:
    add_check(checks, "digest_reference_used", "WARN", "medium", "Image reference does not use digest form", {"image": image_ref})

if sbom_ref:
    add_check(checks, "sbom_available", "PASS", "none", "SBOM reference is available", {"ref": sbom_ref})
else:
    add_check(checks, "sbom_available", "WARN", "high", "SBOM reference is missing", {})

if provenance_ref:
    add_check(checks, "provenance_available", "PASS", "none", "Provenance reference is available", {"ref": provenance_ref})
else:
    add_check(checks, "provenance_available", "WARN", "high", "Provenance reference is missing", {})

if cosign_verified:
    add_check(checks, "cosign_signature_verified", "PASS", "none", "Cosign signature is marked verified", {})
else:
    add_check(checks, "cosign_signature_verified", "WARN", "high", "Cosign signature is not verified", {})

if slsa_level:
    add_check(checks, "slsa_attestation_available", "PASS", "none", "SLSA attestation level is available", {"level": slsa_level})
else:
    add_check(checks, "slsa_attestation_available", "WARN", "medium", "SLSA attestation level is missing", {})

if decision.get("decision") == "BLOCK":
    add_check(checks, "source_supply_chain_decision", "FAIL", "critical", "Source supply-chain decision is BLOCK", decision)
else:
    add_check(checks, "source_supply_chain_decision", "PASS", "none", "Source supply-chain decision is not BLOCK", decision)

blocking_reasons = [c["message"] for c in checks if c["status"] == "FAIL"]
warning_reasons = [c["message"] for c in checks if c["status"] == "WARN"]

if blocking_reasons:
    gate_decision = "BLOCK"
    allowed = False
    requires_human_approval = True
elif warning_reasons:
    gate_decision = "REQUIRE_HUMAN_APPROVAL"
    allowed = False
    requires_human_approval = True
else:
    gate_decision = "ALLOW"
    allowed = True
    requires_human_approval = False

risk_score = min(100, sum(score_for(c["status"], c["severity"]) for c in checks))

gate = {
    "schemaVersion": "signed.release.gate/v1alpha1",
    "signedReleaseGateId": gate_id,
    "generatedBy": "build-signed-release-gate.sh",
    "generatedAt": now(),
    "mode": "read_only_signed_release_gate",
    "source": {
        "supplyChainDecision": str(input_path),
        "supplyChainDecisionId": supply.get("supplyChainDecisionId"),
    },
    "release": release,
    "image": {
        "image": image_ref,
        "imageDigest": image_digest,
        "usesDigestReference": uses_digest_reference,
        "usesMutableTag": uses_mutable_tag,
    },
    "attestations": {
        "sbom": {"ref": sbom_ref, "present": bool(sbom_ref)},
        "provenance": {"ref": provenance_ref, "present": bool(provenance_ref)},
        "cosign": {"verified": cosign_verified},
        "slsa": {"level": slsa_level, "present": bool(slsa_level)},
    },
    "checks": checks,
    "decision": {
        "decision": gate_decision,
        "allowed": allowed,
        "requiresHumanApproval": requires_human_approval,
        "blockingReasons": blocking_reasons,
        "warningReasons": warning_reasons,
    },
    "risk": {
        "riskLevel": risk_level(risk_score),
        "riskScore": risk_score,
    },
    "guardrails": {
        "readOnly": True,
        "willExecute": False,
        "doesNotSignImages": True,
        "doesNotVerifyExternalServices": True,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotBuildImages": True,
        "doesNotPushImages": True,
        "doesNotCommitOrPush": True,
    },
}

output_json.write_text(json.dumps(gate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(json.dumps({
    "schemaVersion": "signed.release.gate.build/v1alpha1",
    "signedReleaseGate": str(output_json),
    "latest": str(latest_json),
    "decision": gate_decision,
    "allowed": allowed,
    "requiresHumanApproval": requires_human_approval,
}, ensure_ascii=False, indent=2))
PY
