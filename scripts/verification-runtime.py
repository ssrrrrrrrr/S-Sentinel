#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ALLOWED_MODES = {"input_derived", "external_command", "admission"}


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def bool_value(value: Any) -> bool:
    return bool(value) if value is not None else False


def build_verification(
    supply_chain_decision: Path,
    mode: str,
    cosign_bin: str,
) -> dict[str, Any]:
    if mode not in ALLOWED_MODES:
        raise SystemExit(f"ERROR: unsupported verification mode={mode}; allowed={sorted(ALLOWED_MODES)}")

    supply = load_json(supply_chain_decision)
    image = as_dict(supply.get("image"))
    attestations = as_dict(supply.get("attestations"))

    sbom = as_dict(attestations.get("sbom"))
    provenance = as_dict(attestations.get("provenance"))
    cosign = as_dict(attestations.get("cosign"))
    slsa = as_dict(attestations.get("slsa"))

    image_ref = nullable_string(image.get("image"))
    image_digest = nullable_string(image.get("imageDigest"))
    uses_digest_reference = bool_value(image.get("usesDigestReference"))

    sbom_ref = nullable_string(sbom.get("ref") or sbom.get("path"))
    provenance_ref = nullable_string(provenance.get("ref") or provenance.get("path"))
    signature_verified = bool_value(cosign.get("verified"))
    slsa_level = nullable_string(slsa.get("level") or slsa.get("slsaLevel"))

    verification_subject = image_ref or image_digest or "<image-reference>"
    normalized_cosign_bin = cosign_bin.strip() or "cosign"
    tool_available = shutil.which(normalized_cosign_bin) is not None

    if mode == "admission":
        tool = "admission"
        tool_binary = None
        command_preview = None
    else:
        tool = "cosign"
        tool_binary = normalized_cosign_bin
        command_preview = [normalized_cosign_bin, "verify", verification_subject]

    return {
        "schemaVersion": "signed.release.gate.verification/v1alpha1",
        "mode": mode,
        "tool": tool,
        "toolBinary": tool_binary,
        "toolAvailable": tool_available if tool_binary else False,
        "command": None,
        "commandPreview": command_preview,
        "exitCode": None,
        "checkedAt": now(),
        "subject": {
            "image": image_ref,
            "imageDigest": image_digest,
        },
        "results": {
            "imageDigestPresent": bool(image_digest),
            "usesDigestReference": uses_digest_reference,
            "signatureVerified": signature_verified,
            "sbomPresent": bool(sbom_ref),
            "provenancePresent": bool(provenance_ref),
            "slsaLevelPresent": bool(slsa_level),
            "slsaLevel": slsa_level,
        },
        "source": {
            "supplyChainDecision": str(supply_chain_decision),
            "attestationsPath": "attestations",
        },
        "guardrails": {
            "readOnly": True,
            "willExecute": False,
            "canRunExternalVerification": False,
            "doesNotRunExternalCommands": True,
            "doesNotVerifyExternalServices": True,
        },
    }


def run_mode(args: argparse.Namespace, mode: str) -> int:
    result = build_verification(
        supply_chain_decision=Path(args.supply_chain_decision),
        mode=mode,
        cosign_bin=args.cosign_bin,
    )
    write_json(Path(args.output), result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--supply-chain-decision", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cosign-bin", default="cosign")


def main() -> int:
    parser = argparse.ArgumentParser(description="S Sentinel verification runtime boundary.")
    sub = parser.add_subparsers(dest="command", required=True)

    input_parser = sub.add_parser("input-derived", help="Build read-only input-derived verification result.")
    add_common_args(input_parser)

    external_parser = sub.add_parser("external-command-preview", help="Build external command preview without execution.")
    add_common_args(external_parser)

    admission_parser = sub.add_parser("admission-placeholder", help="Build admission verification placeholder.")
    add_common_args(admission_parser)

    args = parser.parse_args()

    if args.command == "input-derived":
        return run_mode(args, "input_derived")

    if args.command == "external-command-preview":
        return run_mode(args, "external_command")

    if args.command == "admission-placeholder":
        return run_mode(args, "admission")

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
