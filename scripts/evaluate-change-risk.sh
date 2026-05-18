#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
CHANGE_CONTEXT_FILE="${1:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/evaluate-change-risk.sh [CHANGE_CONTEXT_JSON]

Examples:
  scripts/evaluate-change-risk.sh
  scripts/evaluate-change-risk.sh docs/release-reports/change-context-latest.json
  scripts/evaluate-change-risk.sh docs/release-reports/change-context-20260517-175907.json

Behavior:
  - If CHANGE_CONTEXT_JSON is omitted, docs/release-reports/change-context-latest.json is used.
  - The output is written to:
      change-risk-decision-*.json
      change-risk-decision-latest.json
  - This script is advisory_only.
  - It does not block GitOps, modify Kubernetes, change manifests, rollback, promote, patch, or delete resources.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 1 ]; then
  echo "ERROR: too many arguments" >&2
  usage >&2
  exit 1
fi

if [ -z "$CHANGE_CONTEXT_FILE" ]; then
  CHANGE_CONTEXT_FILE="$REPORT_DIR/change-context-latest.json"
fi

if [ ! -f "$CHANGE_CONTEXT_FILE" ]; then
  echo "ERROR: change context file does not exist: $CHANGE_CONTEXT_FILE" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$CHANGE_CONTEXT_FILE")"
TS="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="$OUTPUT_DIR/change-risk-decision-${TS}.json"
LATEST_FILE="$OUTPUT_DIR/change-risk-decision-latest.json"

python3 - "$CHANGE_CONTEXT_FILE" "$OUTPUT_FILE" "$LATEST_FILE" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ctx_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
latest_path = Path(sys.argv[3])

ctx = json.loads(ctx_path.read_text(encoding="utf-8"))

risk = ctx.get("risk") or {}
score = risk.get("score", 0)
try:
    score = int(score)
except Exception:
    score = 0

score = max(0, min(score, 100))
level = risk.get("level") or "low"
hints = risk.get("hints") or []

image = ctx.get("image") or {}
env = ctx.get("env") or {}
rollout_strategy = ctx.get("rolloutStrategy") or {}
slo_gates = ctx.get("sloGates") or {}

env_changes = env.get("changes") or []
slo_changes = slo_gates.get("changes") or []

matched_rules = ["advisory_only"]

if image.get("changed"):
    matched_rules.append("image_changed")

for ch in env_changes:
    name = ch.get("name", "UNKNOWN")
    matched_rules.append(f"env_changed_{name}")
    if name == "FAULT_RATE":
        matched_rules.append("fault_rate_changed")
    elif name == "LATENCY_MS":
        matched_rules.append("latency_changed")

if rollout_strategy.get("changed"):
    matched_rules.append("rollout_strategy_changed")

if slo_changes:
    matched_rules.append("slo_gate_changed")

if hints:
    matched_rules.extend([f"risk_hint:{h}" for h in hints])

if score >= 80:
    risk_decision = "RECOMMEND_BLOCK"
    normalized_level = "critical"
    requires_human_approval = True
    recommended_action = "manual_review_before_canary"
    reason = "Change risk is critical; blocking is recommended but not enforced in advisory_only mode"
    human_reason = "本次变更风险为 critical，建议发布前人工复核；当前仅给出建议，不会自动阻断发布。"
elif score >= 60:
    risk_decision = "REQUIRE_HUMAN_APPROVAL"
    normalized_level = "high"
    requires_human_approval = True
    recommended_action = "manual_review_before_canary"
    reason = "Change risk is high; human approval is recommended before canary"
    human_reason = "本次变更风险较高，建议进入 canary 前先人工确认；当前仅给出建议，不会自动阻断发布。"
elif score >= 30:
    risk_decision = "ALLOW_CANARY_WITH_NOTICE"
    normalized_level = "medium"
    requires_human_approval = False
    recommended_action = "continue_canary_with_notice"
    reason = "Change risk is medium; canary is allowed with notice"
    human_reason = "本次变更风险为 medium，可以继续进入 canary，但建议关注风险提示。"
else:
    risk_decision = "ALLOW_CANARY"
    normalized_level = "low"
    requires_human_approval = False
    recommended_action = "continue_canary"
    reason = "Change risk is low; canary is allowed"
    human_reason = "本次变更风险较低，可以继续进入 canary。"

decision = {
    "schemaVersion": "release.change-risk/v1alpha1",
    "generatedBy": "evaluate-change-risk.sh",
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "sourceChangeContext": str(ctx_path),
    "executionMode": "advisory_only",
    "change": {
        "changeType": ctx.get("changeType"),
        "app": ctx.get("app"),
        "namespace": ctx.get("namespace"),
        "git": ctx.get("git") or {},
        "imageChanged": bool(image.get("changed", False)),
        "envChangeCount": len(env_changes),
        "sloGateChangeCount": len(slo_changes),
        "rolloutStrategyChanged": bool(rollout_strategy.get("changed", False)),
    },
    "riskDecision": risk_decision,
    "riskLevel": normalized_level,
    "sourceRiskLevel": level,
    "riskScore": score,
    "requiresHumanApproval": requires_human_approval,
    "recommendedAction": recommended_action,
    "reason": reason,
    "humanReason": human_reason,
    "matchedRules": matched_rules,
    "riskHints": hints,
    "guardrails": {
        "autoBlock": False,
        "autoExecute": False,
        "doesNotModifyGitOps": True,
        "doesNotModifyKubernetes": True,
        "doesNotRollback": True,
        "doesNotPromote": True,
        "doesNotPatchResources": True,
        "doesNotDeleteResources": True
    }
}

output_path.write_text(json.dumps(decision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
latest_path.write_text(json.dumps(decision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print(f"Change risk decision generated: {output_path}")
print(f"Latest change risk decision: {latest_path}")
print(json.dumps({
    "riskDecision": risk_decision,
    "riskLevel": normalized_level,
    "riskScore": score,
    "requiresHumanApproval": requires_human_approval,
    "recommendedAction": recommended_action,
}, ensure_ascii=False, indent=2))
PY
