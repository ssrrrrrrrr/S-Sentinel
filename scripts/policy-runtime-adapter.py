#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")




def signed_gate_verification_summary(signed_gate: dict[str, Any]) -> dict[str, Any]:
    verification = signed_gate.get("verification") or {}
    if not isinstance(verification, dict) or not verification:
        return {}

    results = verification.get("results") or {}
    guardrails = verification.get("guardrails") or {}

    return {
        "schemaVersion": verification.get("schemaVersion"),
        "mode": verification.get("mode"),
        "tool": verification.get("tool"),
        "toolBinary": verification.get("toolBinary"),
        "toolAvailable": verification.get("toolAvailable"),
        "signatureVerified": results.get("signatureVerified"),
        "sbomPresent": results.get("sbomPresent"),
        "provenancePresent": results.get("provenancePresent"),
        "slsaLevelPresent": results.get("slsaLevelPresent"),
        "canRunExternalVerification": guardrails.get("canRunExternalVerification"),
        "doesNotRunExternalCommands": guardrails.get("doesNotRunExternalCommands"),
    }

def build_policy_input(ai_decision: Path, policy_file: Path, output: Path, signed_release_gate: Path | None = None) -> None:
    decision = load_json(ai_decision)

    signed_gate: dict[str, Any] = {}
    signed_gate_ref: dict[str, Any] = {
        "file": str(signed_release_gate) if signed_release_gate is not None else None,
        "loaded": False,
    }
    signed_gate_verification: dict[str, Any] = {}

    if signed_release_gate is not None:
        if not signed_release_gate.exists():
            raise SystemExit(f"ERROR: signed release gate does not exist: {signed_release_gate}")
        signed_gate = load_json(signed_release_gate)
        gate_decision = signed_gate.get("decision") or {}
        gate_risk = signed_gate.get("risk") or {}
        signed_gate_verification = signed_gate_verification_summary(signed_gate)
        signed_gate_ref = {
            "file": str(signed_release_gate),
            "loaded": True,
            "schemaVersion": signed_gate.get("schemaVersion"),
            "signedReleaseGateId": signed_gate.get("signedReleaseGateId"),
            "decision": gate_decision.get("decision"),
            "allowed": gate_decision.get("allowed"),
            "requiresHumanApproval": gate_decision.get("requiresHumanApproval"),
            "riskLevel": gate_risk.get("riskLevel"),
            "riskScore": gate_risk.get("riskScore"),
            "verification": signed_gate_verification,
        }

    signed_gate_decision = signed_gate.get("decision") or {}
    raw_input = dict(decision)
    if signed_gate:
        raw_input["signedReleaseGate"] = signed_gate
        raw_input["signedReleaseGateRef"] = signed_gate_ref

    release_id = None
    name = ai_decision.name
    if name.startswith("ai-decision-") and name.endswith(".json"):
        release_id = name[len("ai-decision-"):-len(".json")]

    policy_input = {
        "schemaVersion": "policy.input/v1alpha1",
        "generatedBy": "policy-runtime-adapter.py",
        "generatedAt": now(),
        "releaseId": release_id,
        "sourceDecisionFile": str(ai_decision),
        "policyRef": {
            "file": str(policy_file),
            "loaded": policy_file.exists(),
        },
        "runtime": {
            "requestedRuntime": "local-python",
        },
        "inputSummary": {
            "releaseResult": decision.get("releaseResult"),
            "requestedAction": (
                (decision.get("agentAction") or {}).get("type")
                or decision.get("recommendedAction")
            ),
            "executionMode": decision.get("executionMode"),
            "requiresHumanApproval": decision.get("requiresHumanApproval"),
            "service": decision.get("service"),
            "env": decision.get("env"),
            "sloId": decision.get("sloId"),
            "strategyId": decision.get("strategyId"),
            "signedReleaseGateDecision": signed_gate_decision.get("decision"),
            "signedReleaseGateAllowed": signed_gate_decision.get("allowed"),
            "signedReleaseGateRequiresHumanApproval": signed_gate_decision.get("requiresHumanApproval"),
            "signedReleaseGateVerificationMode": signed_gate_verification.get("mode"),
            "signedReleaseGateVerificationToolAvailable": signed_gate_verification.get("toolAvailable"),
            "signedReleaseGateSignatureVerified": signed_gate_verification.get("signatureVerified"),
            "signedReleaseGateSBOMPresent": signed_gate_verification.get("sbomPresent"),
            "signedReleaseGateProvenancePresent": signed_gate_verification.get("provenancePresent"),
            "signedReleaseGateCanRunExternalVerification": signed_gate_verification.get("canRunExternalVerification"),
        },
        "signedReleaseGateRef": signed_gate_ref,
        "signedReleaseGate": signed_gate,
        "signedReleaseGateVerification": signed_gate_verification,
        "rawInput": raw_input,
    }

    write_json(output, policy_input)


def evaluate_local_python(policy_input_file: Path, output: Path, repo_dir: Path, decision_output: Path | None = None) -> None:
    policy_input = load_json(policy_input_file)
    signed_gate_verification = policy_input.get("signedReleaseGateVerification") or {}

    source_decision_file = Path(str(policy_input.get("sourceDecisionFile") or ""))
    policy_ref = policy_input.get("policyRef") or {}
    policy_file = Path(str(policy_ref.get("file") or "policy/release-policy.yaml"))

    if not source_decision_file.exists():
        raise SystemExit(f"ERROR: sourceDecisionFile does not exist: {source_decision_file}")

    evaluator = repo_dir / "scripts" / "evaluate-agent-decision.sh"
    if not evaluator.exists():
        raise SystemExit(f"ERROR: evaluator not found: {evaluator}")

    with tempfile.TemporaryDirectory(prefix="ssentinel-policy-runtime-") as tmp:
        tmp_dir = Path(tmp)
        ai_copy = tmp_dir / source_decision_file.name
        ai_decision = load_json(source_decision_file)

        if policy_input.get("signedReleaseGate"):
            ai_decision["signedReleaseGate"] = policy_input.get("signedReleaseGate")
        if policy_input.get("signedReleaseGateRef"):
            ai_decision["signedReleaseGateRef"] = policy_input.get("signedReleaseGateRef")

        write_json(ai_copy, ai_decision)

        env = os.environ.copy()
        env["RELEASE_REPORT_DIR"] = str(tmp_dir)
        env["RELEASE_POLICY_FILE"] = str(policy_file)
        env["RELEASE_CONTRACT_VALIDATION_MODE"] = env.get("RELEASE_CONTRACT_VALIDATION_MODE", "warn")

        completed = subprocess.run(
            [str(evaluator), str(ai_copy)],
            cwd=str(repo_dir),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )

        if completed.returncode != 0:
            raise SystemExit(
                "ERROR: local-python policy runtime failed\n"
                + completed.stdout
            )

        suffix = ai_copy.name[len("ai-decision-"):] if ai_copy.name.startswith("ai-decision-") else ai_copy.name
        policy_decision_file = tmp_dir / f"policy-decision-{suffix}"

        if not policy_decision_file.exists():
            raise SystemExit(f"ERROR: policy decision was not generated: {policy_decision_file}")

        policy_decision = load_json(policy_decision_file)

    result = {
        "schemaVersion": "policy.runtime.result/v1alpha1",
        "generatedBy": "policy-runtime-adapter.py",
        "generatedAt": now(),
        "runtime": {
            "name": "local-python",
            "adapter": "evaluate-agent-decision.sh",
            "mode": "subprocess",
        },
        "policyInputRef": str(policy_input_file),
        "policyDecision": policy_decision,
        "signedReleaseGate": policy_decision.get("signedReleaseGate") or {},
        "signedReleaseGateVerification": signed_gate_verification,
        "summary": {
            "policyDecision": policy_decision.get("policyDecision"),
            "finalAction": policy_decision.get("finalAction"),
            "allowed": policy_decision.get("allowed"),
            "requiresHumanApproval": policy_decision.get("requiresHumanApproval"),
            "matchedRules": policy_decision.get("matchedRules") or [],
            "signedReleaseGateDecision": (policy_decision.get("signedReleaseGate") or {}).get("decision"),
            "signedReleaseGateVerificationMode": signed_gate_verification.get("mode"),
            "signedReleaseGateVerificationToolAvailable": signed_gate_verification.get("toolAvailable"),
            "signedReleaseGateSignatureVerified": signed_gate_verification.get("signatureVerified"),
            "signedReleaseGateCanRunExternalVerification": signed_gate_verification.get("canRunExternalVerification"),
        },
        "safety": {
            "readOnly": True,
            "willExecute": False,
            "doesNotModifyKubernetes": True,
            "doesNotModifyGitOps": True,
            "doesNotBuildOrPushImages": True,
        },
    }

    write_json(output, result)
    if decision_output is not None:
        write_json(decision_output, policy_decision)


def main() -> int:
    parser = argparse.ArgumentParser(description="S Sentinel Policy Runtime Adapter.")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build-input")
    build.add_argument("--ai-decision", required=True)
    build.add_argument("--policy-file", default="policy/release-policy.yaml")
    build.add_argument("--signed-release-gate")
    build.add_argument("--output", required=True)

    evaluate = sub.add_parser("evaluate")
    evaluate.add_argument("--runtime", default="local-python", choices=["local-python"])
    evaluate.add_argument("--policy-input", required=True)
    evaluate.add_argument("--output", required=True)
    evaluate.add_argument("--repo-dir", default=".")
    evaluate.add_argument("--decision-output")

    args = parser.parse_args()

    if args.command == "build-input":
        build_policy_input(
            Path(args.ai_decision),
            Path(args.policy_file),
            Path(args.output),
            Path(args.signed_release_gate) if args.signed_release_gate else None,
        )
        return 0

    if args.command == "evaluate":
        evaluate_local_python(
            Path(args.policy_input),
            Path(args.output),
            Path(args.repo_dir).resolve(),
            Path(args.decision_output) if args.decision_output else None,
        )
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
