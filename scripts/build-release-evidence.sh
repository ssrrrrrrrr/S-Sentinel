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

python3 - "$AI_DECISION_FILE" "$POLICY_DECISION_FILE" "$OUTPUT_FILE" "$SUMMARY_FILE" <<'PY'
import json
import sys
from pathlib import Path

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

bundle = {
    "schemaVersion": "release.evidence.bundle/v1alpha1",
    "generatedBy": "build-release-evidence.sh",
    "releaseResult": ai.get("releaseResult", "UNKNOWN"),
    "policyDecision": policy.get("policyDecision", "UNKNOWN"),
    "finalAction": policy.get("finalAction", "UNKNOWN"),
    "executionMode": policy.get("executionMode", ai.get("executionMode", "unknown")),
    "requiresHumanApproval": bool(policy.get("requiresHumanApproval", False)),
    "safeToRetry": bool(ai.get("safeToRetry", False)),
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
            "reason": policy.get("reason"),
            "inputSummary": policy.get("inputSummary") or {},
        },
    },
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Release evidence bundle generated: {output_path}")
PY

cat "$OUTPUT_FILE"
