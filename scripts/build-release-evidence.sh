#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"

AI_DECISION_FILE="${1:-}"
POLICY_DECISION_FILE="${2:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-release-evidence.sh [AI_DECISION_JSON] [POLICY_DECISION_JSON]

Examples:
  scripts/build-release-evidence.sh
  scripts/build-release-evidence.sh docs/release-reports/ai-decision-20260518-211837.json
  scripts/build-release-evidence.sh docs/release-reports/ai-decision-20260518-211837.json docs/release-reports/policy-decision-20260518-211837.json

Behavior:
  - If AI_DECISION_JSON is omitted, the latest docs/release-reports/ai-decision-*.json is used.
  - If POLICY_DECISION_JSON is omitted, the matching policy-decision-*.json is inferred from the ai-decision timestamp.
  - The output is written to docs/release-reports/release-evidence-*.json.
  - This script only builds an evidence index. It does not modify Rollouts, GitOps manifests, or Kubernetes resources.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 2 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ -z "$AI_DECISION_FILE" ]; then
  AI_DECISION_FILE="$(ls -t "$REPORT_DIR"/ai-decision-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$AI_DECISION_FILE" ]; then
  echo "ERROR: no ai-decision-*.json found under $REPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$AI_DECISION_FILE" ]; then
  echo "ERROR: ai decision file does not exist: $AI_DECISION_FILE" >&2
  exit 1
fi

AI_BASENAME="$(basename "$AI_DECISION_FILE")"
AI_SUFFIX="${AI_BASENAME#ai-decision-}"
SUMMARY_FILE="$REPORT_DIR/release-summary-${AI_SUFFIX%.json}.md"

if [ -z "$POLICY_DECISION_FILE" ]; then
  POLICY_DECISION_FILE="$REPORT_DIR/policy-decision-$AI_SUFFIX"
fi

if [ ! -f "$POLICY_DECISION_FILE" ]; then
  echo "ERROR: policy decision file does not exist: $POLICY_DECISION_FILE" >&2
  exit 1
fi

OUTPUT_FILE="$REPORT_DIR/release-evidence-$AI_SUFFIX"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

validate_generated_release_contract() {
  local contract_file="${1:-}"
  local helper="${RELEASE_CONTRACT_VALIDATOR_HELPER:-$SCRIPT_DIR/validate-generated-release-contract.sh}"

  if [ "${RELEASE_CONTRACT_VALIDATION_MODE:-warn}" = "off" ]; then
    return 0
  fi

  if [ -f "$helper" ]; then
    bash "$helper" "$contract_file"
  else
    echo "WARN: release contract validator helper not found: $helper" >&2
  fi
}

python3 - "$AI_DECISION_FILE" "$POLICY_DECISION_FILE" "$OUTPUT_FILE" "$SUMMARY_FILE" <<'PY'
import json
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

ai_path = Path(sys.argv[1])
policy_path = Path(sys.argv[2])
output_path = Path(sys.argv[3])
summary_path = Path(sys.argv[4])

ai = json.loads(ai_path.read_text(encoding="utf-8"))
policy = json.loads(policy_path.read_text(encoding="utf-8"))

sources = ai.get("sources") or {}
rollout = ai.get("rollout") or {}
analysis_run = ai.get("analysisRun") or {}
evidence = ai.get("evidence") or {}

def resolve_existing_path(raw):
    if not raw:
        return None

    candidate = Path(str(raw))
    if candidate.is_absolute():
        return candidate if candidate.exists() else None

    search_roots = [
        Path.cwd(),
        ai_path.parent,
        policy_path.parent,
        output_path.parent,
    ]

    for root in search_roots:
        resolved = root / candidate
        if resolved.exists():
            return resolved

    return None

def read_json_object(path):
    if not path or not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def read_yaml_object(path):
    if not path or not path.exists() or yaml is None:
        return None
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except Exception:
        return None

release_context_path = resolve_existing_path(sources.get("releaseContext"))
release_context = read_json_object(release_context_path)

service = release_context.get("service")
env = release_context.get("env")
slo_id = release_context.get("sloId")
slo_config_ref = release_context.get("sloConfigRef")
slo_config_path = resolve_existing_path(slo_config_ref)
slo_config_snapshot = read_yaml_object(slo_config_path)

strategy_id = release_context.get("strategyId")
strategy_config_ref = release_context.get("strategyConfigRef")
strategy_config_path = resolve_existing_path(strategy_config_ref)
strategy_config_snapshot = read_yaml_object(strategy_config_path)

bundle = {
    "schemaVersion": "release.evidence.bundle/v1alpha1",
    "generatedBy": "build-release-evidence.sh",
    "releaseResult": ai.get("releaseResult", "UNKNOWN"),
    "policyDecision": policy.get("policyDecision", "UNKNOWN"),
    "finalAction": policy.get("finalAction", "UNKNOWN"),
    "policyDecisionId": policy.get("policyDecisionId"),
    "requestedAction": policy.get("requestedAction") or (policy.get("inputSummary") or {}).get("agentActionType"),
    "allowed": policy.get("allowed"),
    "deniedReasons": policy.get("deniedReasons") or [],
    "approvalRequiredReasons": policy.get("approvalRequiredReasons") or [],
    "strategyPolicy": policy.get("strategyPolicy") or {},
    "policySafety": policy.get("safety") or {},
    "executionMode": policy.get("executionMode", ai.get("executionMode", "unknown")),
    "requiresHumanApproval": bool(policy.get("requiresHumanApproval", False)),
    "safeToRetry": bool(ai.get("safeToRetry", False)),
    "service": service,
    "env": env,
    "sloId": slo_id,
    "sloConfigRef": slo_config_ref,
    "sloConfigSnapshot": slo_config_snapshot,
    "strategyId": strategy_id,
    "strategyConfigRef": strategy_config_ref,
    "strategyConfigSnapshot": strategy_config_snapshot,
    "summary": {
        "rolloutPhase": rollout.get("phase") or evidence.get("rolloutPhase"),
        "rolloutAbort": rollout.get("abort") if "abort" in rollout else evidence.get("rolloutAbort"),
        "analysisRunPhase": analysis_run.get("phase") or evidence.get("analysisRunPhase"),
        "riskLevel": ai.get("riskLevel"),
        "riskScore": ai.get("riskScore"),
        "changeRiskLevel": ai.get("changeRiskLevel"),
        "changeRiskScore": ai.get("changeRiskScore"),
        "failedMetrics": ai.get("failedMetrics") or [],
        "matchedPolicyRules": policy.get("matchedRules") or [],
    },
    "artifacts": {
        "releaseContext": sources.get("releaseContext"),
        "releaseReport": sources.get("releaseReport"),
        "aiAdvice": sources.get("aiAdvice"),
        "aiDecision": str(ai_path),
        "policyDecision": str(policy_path),
        "releaseSummary": str(summary_path),
        "actionPlan": None,
        "actionPlanReport": None,
    },
    "decisionRefs": {
        "aiDecision": {
            "decisionSource": ai.get("decisionSource"),
            "confidence": ai.get("confidence"),
            "agentAction": ai.get("agentAction") or {},
            "policyHints": ai.get("policyHints") or [],
            "nextSteps": ai.get("nextSteps") or [],
        },
        "policyDecision": {
            "policyDecisionId": policy.get("policyDecisionId"),
            "requestedAction": policy.get("requestedAction") or (policy.get("inputSummary") or {}).get("agentActionType"),
            "allowed": policy.get("allowed"),
            "reason": policy.get("reason"),
            "deniedReasons": policy.get("deniedReasons") or [],
            "approvalRequiredReasons": policy.get("approvalRequiredReasons") or [],
            "matchedRules": policy.get("matchedRules") or [],
            "strategyPolicy": policy.get("strategyPolicy") or {},
            "safety": policy.get("safety") or {},
            "inputSummary": policy.get("inputSummary") or {},
        },
    },
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Release evidence bundle generated: {output_path}")
PY

validate_generated_release_contract "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
