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


POLICY_RUNTIME_REGISTRY: dict[str, dict[str, Any]] = {
    "local-python": {
        "name": "local-python",
        "phase": "active",
        "runtimeType": "subprocess",
        "adapter": "evaluate-agent-decision.sh",
        "policyLanguage": "python",
        "canEvaluate": True,
        "previewOnly": False,
        "externalDependency": False,
        "requiredBinary": None,
        "description": "Existing deterministic local Python policy evaluator.",
    },
    "opa": {
        "name": "opa",
        "phase": "registered",
        "runtimeType": "external_policy_engine",
        "adapter": "opa eval",
        "policyLanguage": "rego",
        "canEvaluate": False,
        "previewOnly": True,
        "externalDependency": True,
        "requiredBinary": "opa",
        "policyBundleRef": "policy/opa",
        "policyFile": "policy/opa/release_policy.rego",
        "entrypoint": "data.ssentinel.release.decision",
        "inputContract": "policy.input/v1alpha1",
        "outputContract": "release.policy.evaluator/v1alpha1",
        "commandPreviewTemplate": [
            "opa",
            "eval",
            "--format",
            "json",
            "--data",
            "policy/opa",
            "--input",
            "${POLICY_INPUT}",
            "data.ssentinel.release.decision"
        ],
        "description": "Preview-only OPA/Rego policy runtime placeholder.",
    },
    "kyverno-cli": {
        "name": "kyverno-cli",
        "phase": "registered",
        "runtimeType": "external_policy_engine",
        "adapter": "kyverno apply",
        "policyLanguage": "kyverno",
        "canEvaluate": False,
        "previewOnly": True,
        "externalDependency": True,
        "requiredBinary": "kyverno",
        "policyBundleRef": "policy/kyverno",
        "policyFile": "policy/kyverno/release-policy.yaml",
        "entrypoint": "ClusterPolicy/ssentinel-release-policy-preview",
        "inputContract": "policy.input/v1alpha1",
        "outputContract": "release.policy.evaluator/v1alpha1",
        "commandPreviewTemplate": [
            "kyverno",
            "apply",
            "policy/kyverno",
            "--resource",
            "${POLICY_INPUT}",
            "--policy-report"
        ],
        "description": "Preview-only Kyverno CLI policy runtime placeholder.",
    },
    "validating-admission-policy-sim": {
        "name": "validating-admission-policy-sim",
        "phase": "registered",
        "runtimeType": "simulator",
        "adapter": "validating-admission-policy-sim",
        "policyLanguage": "cel",
        "canEvaluate": False,
        "previewOnly": True,
        "externalDependency": False,
        "requiredBinary": None,
        "description": "Preview-only ValidatingAdmissionPolicy simulation placeholder.",
    },
}


def runtime_names() -> list[str]:
    return list(POLICY_RUNTIME_REGISTRY.keys())


def runtime_capability(runtime_name: str) -> dict[str, Any]:
    if runtime_name not in POLICY_RUNTIME_REGISTRY:
        raise SystemExit(f"ERROR: unsupported policy runtime: {runtime_name}")
    capability = dict(POLICY_RUNTIME_REGISTRY[runtime_name])
    capability["guardrails"] = {
        "readOnly": True,
        "willExecute": False,
        "previewOnly": bool(capability.get("previewOnly")),
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotBuildOrPushImages": True,
        "doesNotRunExternalCommands": bool(capability.get("previewOnly")),
    }
    return capability


def runtime_registry_document() -> dict[str, Any]:
    return {
        "schemaVersion": "policy.runtime.registry/v1alpha1",
        "generatedBy": "policy-runtime-adapter.py",
        "generatedAt": now(),
        "defaultRuntime": "local-python",
        "runtimes": [runtime_capability(name) for name in runtime_names()],
    }


def runtime_command_preview(runtime_name: str, policy_input_file: Path | None = None) -> list[str] | None:
    capability = POLICY_RUNTIME_REGISTRY.get(runtime_name) or {}
    template = capability.get("commandPreviewTemplate")
    if not isinstance(template, list):
        return None

    policy_input_ref = str(policy_input_file) if policy_input_file is not None else "${POLICY_INPUT}"
    return [
        policy_input_ref if item == "${POLICY_INPUT}" else str(item)
        for item in template
    ]


def preview_policy_decision(policy_input: dict[str, Any], runtime_name: str) -> dict[str, Any]:
    input_summary = policy_input.get("inputSummary") or {}
    release_id = policy_input.get("releaseId")
    reason = f"Policy runtime {runtime_name} is registered but preview-only; no external policy engine was executed"

    return {
        "schemaVersion": "release.policy.evaluator/v1alpha1",
        "policyDecisionId": f"pd-preview-{release_id or runtime_name}",
        "sourceDecisionFile": policy_input.get("sourceDecisionFile"),
        "releaseId": release_id,
        "evidenceId": None,
        "service": input_summary.get("service"),
        "env": input_summary.get("env"),
        "sloId": input_summary.get("sloId"),
        "strategyId": input_summary.get("strategyId"),
        "policyDecision": "REQUIRE_HUMAN_APPROVAL",
        "requestedAction": input_summary.get("requestedAction"),
        "allowed": False,
        "finalAction": "MANUAL_REVIEW",
        "executionMode": "advisory_only",
        "requiresHumanApproval": True,
        "reason": reason,
        "deniedReasons": [],
        "approvalRequiredReasons": ["policy_runtime_preview_only"],
        "matchedRules": ["policy_runtime_preview_only"],
        "signedReleaseGate": policy_input.get("signedReleaseGateRef") or {},
        "inputSummary": input_summary,
        "safety": {
            "readOnly": True,
            "willExecute": False,
            "previewOnly": True,
            "doesNotModifyKubernetes": True,
            "doesNotModifyGitOps": True,
            "doesNotBuildOrPushImages": True,
            "doesNotRunExternalCommands": True,
        },
        "policyRef": policy_input.get("policyRef") or {},
    }


def evaluate_preview_runtime(
    runtime_name: str,
    policy_input_file: Path,
    output: Path,
    decision_output: Path | None = None,
) -> None:
    policy_input = load_json(policy_input_file)
    capability = runtime_capability(runtime_name)
    signed_gate_verification = policy_input.get("signedReleaseGateVerification") or {}
    policy_decision = preview_policy_decision(policy_input, runtime_name)

    result = {
        "schemaVersion": "policy.runtime.result/v1alpha1",
        "generatedBy": "policy-runtime-adapter.py",
        "generatedAt": now(),
        "runtime": {
            **capability,
            "status": "preview_only",
            "mode": "registry_preview",
            "commandPreview": runtime_command_preview(runtime_name, policy_input_file),
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
            "runtimeStatus": "preview_only",
            "runtimePreviewOnly": True,
            "signedReleaseGateDecision": (policy_decision.get("signedReleaseGate") or {}).get("decision"),
            "signedReleaseGateVerificationMode": signed_gate_verification.get("mode"),
            "signedReleaseGateVerificationToolAvailable": signed_gate_verification.get("toolAvailable"),
            "signedReleaseGateSignatureVerified": signed_gate_verification.get("signatureVerified"),
            "signedReleaseGateCanRunExternalVerification": signed_gate_verification.get("canRunExternalVerification"),
            "signedReleaseGateExternalVerificationRequested": signed_gate_verification.get("externalVerificationRequested"),
            "signedReleaseGateExternalVerificationAllowed": signed_gate_verification.get("externalVerificationAllowed"),
            "signedReleaseGateExternalVerificationExecuted": signed_gate_verification.get("externalVerificationExecuted"),
            "signedReleaseGateExternalVerificationSucceeded": signed_gate_verification.get("externalVerificationSucceeded"),
            "signedReleaseGateExternalVerificationSkippedReason": signed_gate_verification.get("externalVerificationSkippedReason"),
        },
        "safety": {
            "readOnly": True,
            "willExecute": False,
            "previewOnly": True,
            "doesNotModifyKubernetes": True,
            "doesNotModifyGitOps": True,
            "doesNotBuildOrPushImages": True,
            "doesNotRunExternalCommands": True,
        },
    }

    write_json(output, result)
    if decision_output is not None:
        write_json(decision_output, policy_decision)




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
        "externalVerificationRequested": results.get("externalVerificationRequested"),
        "externalVerificationAllowed": results.get("externalVerificationAllowed"),
        "externalVerificationExecuted": results.get("externalVerificationExecuted"),
        "externalVerificationSucceeded": results.get("externalVerificationSucceeded"),
        "externalVerificationSkippedReason": results.get("externalVerificationSkippedReason"),
        "canRunExternalVerification": guardrails.get("canRunExternalVerification"),
        "doesNotRunExternalCommands": guardrails.get("doesNotRunExternalCommands"),
    }

def build_policy_input(
    ai_decision: Path,
    policy_file: Path,
    output: Path,
    signed_release_gate: Path | None = None,
    requested_runtime: str = "local-python",
) -> None:
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

    requested_runtime_capability = runtime_capability(requested_runtime)

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
            "requestedRuntime": requested_runtime,
            "capability": requested_runtime_capability,
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
            "signedReleaseGateExternalVerificationRequested": signed_gate_verification.get("externalVerificationRequested"),
            "signedReleaseGateExternalVerificationAllowed": signed_gate_verification.get("externalVerificationAllowed"),
            "signedReleaseGateExternalVerificationExecuted": signed_gate_verification.get("externalVerificationExecuted"),
            "signedReleaseGateExternalVerificationSucceeded": signed_gate_verification.get("externalVerificationSucceeded"),
            "signedReleaseGateExternalVerificationSkippedReason": signed_gate_verification.get("externalVerificationSkippedReason"),
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
            "signedReleaseGateExternalVerificationRequested": signed_gate_verification.get("externalVerificationRequested"),
            "signedReleaseGateExternalVerificationAllowed": signed_gate_verification.get("externalVerificationAllowed"),
            "signedReleaseGateExternalVerificationExecuted": signed_gate_verification.get("externalVerificationExecuted"),
            "signedReleaseGateExternalVerificationSucceeded": signed_gate_verification.get("externalVerificationSucceeded"),
            "signedReleaseGateExternalVerificationSkippedReason": signed_gate_verification.get("externalVerificationSkippedReason"),
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

    list_runtimes = sub.add_parser("list-runtimes")
    list_runtimes.add_argument("--output")

    build = sub.add_parser("build-input")
    build.add_argument("--ai-decision", required=True)
    build.add_argument("--policy-file", default="policy/release-policy.yaml")
    build.add_argument("--signed-release-gate")
    build.add_argument("--runtime", default="local-python", choices=runtime_names())
    build.add_argument("--output", required=True)

    evaluate = sub.add_parser("evaluate")
    evaluate.add_argument("--runtime", default="local-python", choices=runtime_names())
    evaluate.add_argument("--policy-input", required=True)
    evaluate.add_argument("--output", required=True)
    evaluate.add_argument("--repo-dir", default=".")
    evaluate.add_argument("--decision-output")

    args = parser.parse_args()

    if args.command == "list-runtimes":
        result = runtime_registry_document()
        if args.output:
            write_json(Path(args.output), result)
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    if args.command == "build-input":
        build_policy_input(
            Path(args.ai_decision),
            Path(args.policy_file),
            Path(args.output),
            Path(args.signed_release_gate) if args.signed_release_gate else None,
            args.runtime,
        )
        return 0

    if args.command == "evaluate":
        if args.runtime == "local-python":
            evaluate_local_python(
                Path(args.policy_input),
                Path(args.output),
                Path(args.repo_dir),
                Path(args.decision_output) if args.decision_output else None,
            )
        else:
            evaluate_preview_runtime(
                args.runtime,
                Path(args.policy_input),
                Path(args.output),
                Path(args.decision_output) if args.decision_output else None,
            )
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
