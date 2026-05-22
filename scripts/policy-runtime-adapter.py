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


def build_policy_input(ai_decision: Path, policy_file: Path, output: Path) -> None:
    decision = load_json(ai_decision)

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
        },
        "rawInput": decision,
    }

    write_json(output, policy_input)


def evaluate_local_python(policy_input_file: Path, output: Path, repo_dir: Path) -> None:
    policy_input = load_json(policy_input_file)

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
        shutil.copy2(source_decision_file, ai_copy)

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
        "summary": {
            "policyDecision": policy_decision.get("policyDecision"),
            "finalAction": policy_decision.get("finalAction"),
            "allowed": policy_decision.get("allowed"),
            "requiresHumanApproval": policy_decision.get("requiresHumanApproval"),
            "matchedRules": policy_decision.get("matchedRules") or [],
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


def main() -> int:
    parser = argparse.ArgumentParser(description="S Sentinel Policy Runtime Adapter.")
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build-input")
    build.add_argument("--ai-decision", required=True)
    build.add_argument("--policy-file", default="policy/release-policy.yaml")
    build.add_argument("--output", required=True)

    evaluate = sub.add_parser("evaluate")
    evaluate.add_argument("--runtime", default="local-python", choices=["local-python"])
    evaluate.add_argument("--policy-input", required=True)
    evaluate.add_argument("--output", required=True)
    evaluate.add_argument("--repo-dir", default=".")

    args = parser.parse_args()

    if args.command == "build-input":
        build_policy_input(
            Path(args.ai_decision),
            Path(args.policy_file),
            Path(args.output),
        )
        return 0

    if args.command == "evaluate":
        evaluate_local_python(
            Path(args.policy_input),
            Path(args.output),
            Path(args.repo_dir).resolve(),
        )
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
