#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
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


def env_truthy(name: str) -> bool:
    value = os.environ.get(name, "").strip().lower()
    return value in {"1", "true", "yes", "y", "on"}


def truncate_text(value: str, limit: int = 4000) -> str:
    if len(value) <= limit:
        return value
    return value[:limit] + "\n...[truncated]"


def verification_status(
    mode: str,
    allow_external_command: bool,
    tool_available: bool,
    external_executed: bool,
    external_succeeded: bool | None,
) -> str:
    if mode == "input_derived":
        return "input_derived"
    if mode == "admission":
        return "admission_placeholder"
    if mode != "external_command":
        return "unknown"

    if external_executed and external_succeeded is True:
        return "external_verification_passed"
    if external_executed and external_succeeded is False:
        return "external_verification_failed"
    if not allow_external_command:
        return "external_command_disabled"
    if not tool_available:
        return "external_tool_unavailable"
    return "external_verification_unavailable"


def build_verification(
    supply_chain_decision: Path,
    mode: str,
    cosign_bin: str,
    allow_external_command: bool = False,
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

    if mode == "admission":
        tool = "admission"
        tool_binary = None
        command_preview = None
        tool_available = False
    else:
        tool = "cosign"
        tool_binary = normalized_cosign_bin
        command_preview = [normalized_cosign_bin, "verify", verification_subject]
        tool_available = shutil.which(normalized_cosign_bin) is not None

    external_requested = mode == "external_command"
    external_allowed = bool(external_requested and allow_external_command)
    can_run_external = bool(external_allowed and tool_available and command_preview)
    external_executed = False
    external_succeeded: bool | None = None
    skipped_reason: str | None = None
    command: list[str] | None = None
    exit_code: int | None = None
    stdout: str | None = None

    if external_requested and can_run_external:
        completed = subprocess.run(
            command_preview,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=30,
        )
        external_executed = True
        external_succeeded = completed.returncode == 0
        command = command_preview
        exit_code = completed.returncode
        stdout = truncate_text(completed.stdout or "")
    elif external_requested and not allow_external_command:
        skipped_reason = "external_command_not_enabled"
    elif external_requested and not tool_available:
        skipped_reason = "tool_not_available"
    else:
        skipped_reason = "mode_does_not_execute_external_command"

    status = verification_status(
        mode=mode,
        allow_external_command=allow_external_command,
        tool_available=tool_available,
        external_executed=external_executed,
        external_succeeded=external_succeeded,
    )

    return {
        "schemaVersion": "signed.release.gate.verification/v1alpha1",
        "verificationStatus": status,
        "mode": mode,
        "tool": tool,
        "toolBinary": tool_binary,
        "toolAvailable": tool_available if tool_binary else False,
        "command": command,
        "commandPreview": command_preview,
        "exitCode": exit_code,
        "stdout": stdout,
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
            "externalVerificationRequested": external_requested,
            "externalVerificationAllowed": external_allowed,
            "externalVerificationExecuted": external_executed,
            "externalVerificationSucceeded": external_succeeded,
            "externalVerificationSkippedReason": skipped_reason,
            "verificationStatus": status,
        },
        "source": {
            "supplyChainDecision": str(supply_chain_decision),
            "attestationsPath": "attestations",
        },
        "guardrails": {
            "readOnly": True,
            "willExecute": external_executed,
            "canRunExternalVerification": can_run_external,
            "doesNotRunExternalCommands": not external_executed,
            "doesNotVerifyExternalServices": not external_executed,
        },
    }


def run_mode(args: argparse.Namespace, mode: str) -> int:
    allow_external_command = bool(
        args.allow_external_command
        or env_truthy("S_SENTINEL_VERIFICATION_ALLOW_EXTERNAL_COMMAND")
    )

    result = build_verification(
        supply_chain_decision=Path(args.supply_chain_decision),
        mode=mode,
        cosign_bin=args.cosign_bin,
        allow_external_command=allow_external_command,
    )
    write_json(Path(args.output), result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--supply-chain-decision", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cosign-bin", default="cosign")
    parser.add_argument(
        "--allow-external-command",
        action="store_true",
        help="Allow external verification command execution. Default is preview only.",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="S Sentinel verification runtime boundary.")
    sub = parser.add_subparsers(dest="command", required=True)

    input_parser = sub.add_parser("input-derived", help="Build read-only input-derived verification result.")
    add_common_args(input_parser)

    external_parser = sub.add_parser("external-command-preview", help="Build external command verification result. Preview-only unless explicitly allowed.")
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
