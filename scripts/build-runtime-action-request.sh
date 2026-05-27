#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
INPUT_FILE="${1:-latest}"
REQUESTED_BY="${REQUESTED_BY:-runtime-recommendation-controller}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-runtime-action-request.sh [latest|RUNTIME_ACTION_RECOMMENDATION_JSON]

Environment:
  RELEASE_REPORT_DIR                  Optional report directory.
  RUNTIME_ACTION_REQUEST_OUTPUT_DIR   Optional output directory.
  REQUESTED_BY                        Optional requester.

Behavior:
  - Reads runtime-action-recommendation-*.json.
  - Generates runtime-action-request-*.json and runtime-action-request-latest.json.
  - Creates a request-only runtime action record.
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
  INPUT_FILE="$(ls -t "$REPORT_DIR"/runtime-action-recommendation-*.json 2>/dev/null | grep -v 'runtime-action-recommendation-latest.json' | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: runtime action recommendation file does not exist: ${INPUT_FILE:-not provided}" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#runtime-action-recommendation-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_DIR="${RUNTIME_ACTION_REQUEST_OUTPUT_DIR:-$(dirname "$INPUT_FILE")}"
mkdir -p "$OUTPUT_DIR"

OUTPUT_JSON="$OUTPUT_DIR/runtime-action-request-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/runtime-action-request-latest.json"

python3 - "$INPUT_FILE" "$OUTPUT_JSON" "$LATEST_JSON" "$REQUESTED_BY" <<'PY'
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
requested_by = sys.argv[4] or "runtime-recommendation-controller"

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

def first_not_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def derive_request(
    recommended_action: str,
    recommendation_status: str,
    approval_required: bool,
    risk_level: str,
) -> dict[str, Any]:
    if recommended_action in {"", "NOOP", "NONE"}:
        return {
            "requestedAction": "NOOP",
            "requestStatus": "NO_ACTION_REQUESTED",
            "lifecycleStage": "NO_ACTION_REQUESTED",
            "approvalRequired": False,
            "readyToExecute": False,
            "allowedToRequest": False,
            "blockingReasons": ["recommendation_does_not_require_runtime_action"],
        }

    if recommended_action == "REQUIRE_REVIEW" or recommendation_status == "REVIEW_RECOMMENDED":
        return {
            "requestedAction": "REQUIRE_REVIEW",
            "requestStatus": "REVIEW_REQUIRED",
            "lifecycleStage": "WAITING_REVIEW",
            "approvalRequired": True,
            "readyToExecute": False,
            "allowedToRequest": True,
            "blockingReasons": [],
        }

    if recommended_action == "PAUSE_ROLLOUT":
        return {
            "requestedAction": "PAUSE_ROLLOUT",
            "requestStatus": "PENDING_APPROVAL" if approval_required else "READY_FOR_PREFLIGHT",
            "lifecycleStage": "WAITING_APPROVAL" if approval_required else "READY_FOR_PREFLIGHT",
            "approvalRequired": bool(approval_required or risk_level in {"high", "critical"}),
            "readyToExecute": False,
            "allowedToRequest": True,
            "blockingReasons": [],
        }

    return {
        "requestedAction": recommended_action,
        "requestStatus": "UNSUPPORTED_ACTION",
        "lifecycleStage": "BLOCKED",
        "approvalRequired": True,
        "readyToExecute": False,
        "allowedToRequest": False,
        "blockingReasons": ["unsupported_runtime_action"],
    }

recommendation_doc = load_json(input_path)
release = as_dict(recommendation_doc.get("release"))
target = as_dict(recommendation_doc.get("target"))
recommendation = as_dict(recommendation_doc.get("recommendation"))
snapshot = as_dict(recommendation_doc.get("runtimeSnapshot"))
evidence_refs = as_dict(recommendation_doc.get("evidenceRefs"))
source_guardrails = as_dict(recommendation_doc.get("guardrails"))

release_id = str(first_not_empty(release.get("releaseId"), input_path.stem.replace("runtime-action-recommendation-", "")))
recommended_action = str(recommendation.get("recommendedAction") or "NOOP")
recommendation_status = str(recommendation.get("recommendationStatus") or "UNKNOWN")
risk_level = str(recommendation.get("riskLevel") or "unknown")
approval_required = bool(recommendation.get("approvalRequired", False))

derived = derive_request(
    recommended_action,
    recommendation_status,
    approval_required,
    risk_level,
)

runtime_action_request_id = "rarq-" + release_id

doc = {
    "schemaVersion": "runtime.action.request/v1alpha1",
    "runtimeActionRequestId": runtime_action_request_id,
    "generatedBy": "build-runtime-action-request.sh",
    "generatedAt": now(),
    "mode": "request_only",
    "sourceRuntimeActionRecommendationId": recommendation_doc.get("runtimeActionRecommendationId"),
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
        "namespace": target.get("namespace"),
        "rolloutName": target.get("rolloutName"),
        "service": first_not_empty(target.get("service"), release.get("service")),
        "env": first_not_empty(target.get("env"), release.get("env")),
    },
    "request": {
        "requestedBy": requested_by,
        "requestedAction": derived["requestedAction"],
        "requestStatus": derived["requestStatus"],
        "lifecycleStage": derived["lifecycleStage"],
        "requestReason": recommendation.get("summary"),
        "riskLevel": risk_level,
        "confidence": recommendation.get("confidence"),
        "approvalRequired": derived["approvalRequired"],
        "readyToExecute": derived["readyToExecute"],
        "willExecute": False,
    },
    "recommendationBinding": {
        "recommendationStatus": recommendation_status,
        "recommendedAction": recommended_action,
        "approvalRequired": approval_required,
        "reasons": [str(item) for item in as_list(recommendation.get("reasons"))],
        "allowedToRequest": derived["allowedToRequest"],
        "blockingReasons": derived["blockingReasons"],
        "willExecute": False,
    },
    "runtimeSnapshot": {
        "rolloutPhase": snapshot.get("rolloutPhase"),
        "strategy": snapshot.get("strategy"),
        "currentStepIndex": snapshot.get("currentStepIndex"),
        "replicas": snapshot.get("replicas"),
        "updatedReplicas": snapshot.get("updatedReplicas"),
        "readyReplicas": snapshot.get("readyReplicas"),
        "availableReplicas": snapshot.get("availableReplicas"),
        "paused": snapshot.get("paused"),
        "degraded": snapshot.get("degraded"),
        "analysisRunName": snapshot.get("analysisRunName"),
        "analysisStatus": snapshot.get("analysisStatus"),
    },
    "approval": {
        "required": derived["approvalRequired"],
        "status": "NOT_APPROVED" if derived["approvalRequired"] else "NOT_REQUIRED",
        "approved": False,
        "approvalDecision": None,
        "readyToExecute": False,
        "willExecuteAfterApproval": False,
    },
    "evidenceRefs": {
        "runtimeActionRecommendation": str(input_path),
        "sourceRuntimeActionRecommendationId": recommendation_doc.get("runtimeActionRecommendationId"),
        "rolloutRuntimeInspect": evidence_refs.get("rolloutRuntimeInspect"),
        "sourceRolloutRuntimeInspectId": evidence_refs.get("sourceRolloutRuntimeInspectId"),
    },
    "guardrails": {
        "requestOnly": True,
        "readOnly": True,
        "willExecute": False,
        "doesNotPause": True,
        "doesNotResume": True,
        "doesNotPromote": True,
        "doesNotAbort": True,
        "doesNotRollback": True,
        "doesNotModifyKubernetes": True,
        "doesNotModifyGitOps": True,
        "doesNotCommitOrPush": True,
        "sourceRecommendationWillExecute": source_guardrails.get("willExecute"),
    },
}

text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
output_json.write_text(text, encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Runtime action request generated: {output_json}")
print(f"Latest runtime action request: {latest_json}")
print(json.dumps({
    "runtimeActionRequestId": runtime_action_request_id,
    "releaseId": release_id,
    "requestedAction": doc["request"]["requestedAction"],
    "requestStatus": doc["request"]["requestStatus"],
    "lifecycleStage": doc["request"]["lifecycleStage"],
    "willExecute": False,
}, indent=2))
PY
