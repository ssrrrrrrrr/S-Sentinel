#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-runtime-action-recommendation.sh [latest|ROLLOUT_RUNTIME_INSPECT_JSON]

Environment:
  RELEASE_REPORT_DIR                         Optional report directory.
  RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR   Optional output directory.

Behavior:
  - Reads rollout-runtime-inspect-*.json.
  - Generates runtime-action-recommendation-*.json and runtime-action-recommendation-latest.json.
  - Produces a recommendation only.
  - Does not execute pause, resume, promote, abort, rollback, kubectl mutation, GitOps write, or Kubernetes modification.
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
  INPUT_FILE="$(ls -t "$REPORT_DIR"/rollout-runtime-inspect-*.json 2>/dev/null | grep -v 'rollout-runtime-inspect-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: rollout runtime inspect file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#rollout-runtime-inspect-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_DIR="${RUNTIME_ACTION_RECOMMENDATION_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/runtime-action-recommendation-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/runtime-action-recommendation-latest.json"

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

def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None

def first_not_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def bool_value(value: Any) -> bool:
    return value is True

def derive_recommendation(rollout: dict[str, Any], analysis: dict[str, Any], pods: dict[str, Any]) -> dict[str, Any]:
    phase = str(rollout.get("phase") or "Unknown")
    analysis_status = str(analysis.get("status") or "Unknown")
    replicas = rollout.get("replicas")
    ready_replicas = rollout.get("readyReplicas")
    pod_count = pods.get("podCount")
    ready_pod_count = pods.get("readyPodCount")

    reasons: list[str] = []

    degraded = bool_value(rollout.get("degraded")) or phase == "Degraded"
    failed_analysis = analysis_status in {"Failed", "Error", "Inconclusive"}
    insufficient_replicas = isinstance(replicas, int) and isinstance(ready_replicas, int) and ready_replicas < replicas
    no_ready_pods = isinstance(pod_count, int) and pod_count > 0 and ready_pod_count == 0

    if degraded:
        reasons.append("rollout_phase_degraded")
    if failed_analysis:
        reasons.append("analysis_not_successful")
    if insufficient_replicas:
        reasons.append("ready_replicas_below_desired")
    if no_ready_pods:
        reasons.append("no_ready_pods")

    if reasons:
        return {
            "recommendationStatus": "ACTION_RECOMMENDED",
            "recommendedAction": "PAUSE_ROLLOUT",
            "riskLevel": "high",
            "confidence": "high",
            "approvalRequired": True,
            "reasons": reasons,
            "summary": "Runtime evidence indicates rollout risk; recommend preparing a pause request.",
        }

    if bool_value(rollout.get("paused")):
        return {
            "recommendationStatus": "NO_ACTION_REQUIRED",
            "recommendedAction": "NOOP",
            "riskLevel": "medium",
            "confidence": "medium",
            "approvalRequired": False,
            "reasons": ["rollout_already_paused"],
            "summary": "Rollout is already paused; no additional runtime action is recommended.",
        }

    if phase == "Healthy" and analysis_status in {"Successful", "NotFound"} and replicas == ready_replicas:
        return {
            "recommendationStatus": "NO_ACTION_REQUIRED",
            "recommendedAction": "NOOP",
            "riskLevel": "low",
            "confidence": "high",
            "approvalRequired": False,
            "reasons": ["rollout_healthy"],
            "summary": "Rollout appears healthy; no runtime action is recommended.",
        }

    return {
        "recommendationStatus": "REVIEW_RECOMMENDED",
        "recommendedAction": "REQUIRE_REVIEW",
        "riskLevel": "medium",
        "confidence": "medium",
        "approvalRequired": True,
        "reasons": ["rollout_not_terminal_or_insufficient_confidence"],
        "summary": "Runtime state is not clearly healthy or failed; human review is recommended before runtime action.",
    }

inspect = load_json(input_path)
release = as_dict(inspect.get("release"))
target = as_dict(inspect.get("target"))
rollout = as_dict(inspect.get("rollout"))
analysis = as_dict(inspect.get("analysis"))
pods = as_dict(inspect.get("pods"))

release_id = str(first_not_empty(release.get("releaseId"), input_path.stem.replace("rollout-runtime-inspect-", "")))
recommendation = derive_recommendation(rollout, analysis, pods)

doc = {
    "schemaVersion": "runtime.action.recommendation/v1alpha1",
    "runtimeActionRecommendationId": "rar-" + release_id,
    "generatedBy": "build-runtime-action-recommendation.sh",
    "generatedAt": now(),
    "mode": "recommendation_only",
    "release": {
        "releaseId": release_id,
        "service": first_not_empty(release.get("service"), target.get("service")),
        "env": first_not_empty(release.get("env"), target.get("env")),
        "namespace": first_not_empty(release.get("namespace"), target.get("namespace")),
        "policyDecision": release.get("policyDecision"),
        "finalAction": release.get("finalAction"),
    },
    "target": {
        "cluster": target.get("cluster"),
        "namespace": first_not_empty(target.get("namespace"), rollout.get("namespace")),
        "rolloutName": first_not_empty(target.get("rolloutName"), rollout.get("name")),
        "service": first_not_empty(target.get("service"), release.get("service")),
        "env": first_not_empty(target.get("env"), release.get("env")),
    },
    "recommendation": recommendation,
    "runtimeSnapshot": {
        "rolloutPhase": rollout.get("phase"),
        "strategy": rollout.get("strategy"),
        "currentStepIndex": rollout.get("currentStepIndex"),
        "replicas": rollout.get("replicas"),
        "updatedReplicas": rollout.get("updatedReplicas"),
        "readyReplicas": rollout.get("readyReplicas"),
        "availableReplicas": rollout.get("availableReplicas"),
        "paused": rollout.get("paused"),
        "degraded": rollout.get("degraded"),
        "analysisRunName": analysis.get("analysisRunName"),
        "analysisStatus": analysis.get("status"),
        "podCount": pods.get("podCount"),
        "readyPodCount": pods.get("readyPodCount"),
        "runningPodCount": pods.get("runningPodCount"),
    },
    "evidenceRefs": {
        "rolloutRuntimeInspect": str(input_path),
        "sourceRolloutRuntimeInspectId": inspect.get("rolloutRuntimeInspectId"),
    },
    "guardrails": {
        "readOnly": True,
        "recommendationOnly": True,
        "willExecute": False,
        "doesNotPause": True,
        "doesNotResume": True,
        "doesNotPromote": True,
        "doesNotAbort": True,
        "doesNotRollback": True,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotCommitOrPush": True,
    },
}

text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
output_json.write_text(text, encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Runtime action recommendation generated: {output_json}")
print(f"Latest runtime action recommendation: {latest_json}")
print(json.dumps({
    "runtimeActionRecommendationId": doc["runtimeActionRecommendationId"],
    "releaseId": release_id,
    "recommendedAction": recommendation["recommendedAction"],
    "recommendationStatus": recommendation["recommendationStatus"],
    "riskLevel": recommendation["riskLevel"],
    "willExecute": False,
}, indent=2))
PY
