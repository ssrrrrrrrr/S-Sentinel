#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="docs/release-reports"
POLICY_FILE="${RELEASE_POLICY_FILE:-policy/release-policy.yaml}"

usage() {
  cat <<'EOF'
Usage:
  scripts/evaluate-agent-decision.sh [AI_DECISION_JSON]

Examples:
  scripts/evaluate-agent-decision.sh
  scripts/evaluate-agent-decision.sh docs/release-reports/ai-decision-20260518-192351.json

Behavior:
  - If AI_DECISION_JSON is omitted, the latest docs/release-reports/ai-decision-*.json is used.
  - The output is written to docs/release-reports/policy-decision-*.json.
  - Policy defaults are read from policy/release-policy.yaml unless RELEASE_POLICY_FILE is set.
  - This evaluator is advisory-only. It does not modify Rollouts, GitOps manifests, or Kubernetes resources.
EOF
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

INPUT_FILE="${1:-}"

if [ -z "$INPUT_FILE" ]; then
  INPUT_FILE="$(ls -t "$REPORT_DIR"/ai-decision-*.json 2>/dev/null | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ]; then
  echo "ERROR: no ai-decision-*.json found under $REPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: input file does not exist: $INPUT_FILE" >&2
  exit 1
fi

BASENAME="$(basename "$INPUT_FILE")"
SUFFIX="${BASENAME#ai-decision-}"
OUTPUT_FILE="$REPORT_DIR/policy-decision-$SUFFIX"

python3 - "$INPUT_FILE" "$OUTPUT_FILE" "$POLICY_FILE" <<'PY'
import json
import sys
from pathlib import Path

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
policy_path = Path(sys.argv[3])

with input_path.open("r", encoding="utf-8") as f:
    decision = json.load(f)

def parse_scalar(value):
    value = value.strip().strip('"').strip("'")
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    return value

def load_policy(path: Path):
    policy = {
        "executionMode": "advisory_only",
        "autoExecute": False,
        "blockedActions": [],
        "allowedActions": [],
        "dangerousActions": [
            "ROLLBACK",
            "PROMOTE",
            "DELETE_RESOURCE",
            "PATCH_GITOPS",
            "SCALE_DOWN",
            "RESTART_WORKLOAD",
        ],
        "rules": {},
        "source": str(path),
        "loaded": False,
    }

    if not path.exists():
        return policy

    current_list_key = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line.strip():
            continue

        stripped = line.strip()

        if stripped.startswith("- ") and current_list_key:
            policy.setdefault(current_list_key, []).append(parse_scalar(stripped[2:]))
            continue

        current_list_key = None

        if ":" not in stripped:
            continue

        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()

        if not value:
            if key in {"blockedActions", "allowedActions", "dangerousActions"}:
                policy[key] = []
                current_list_key = key
            else:
                policy[key] = {}
            continue

        parsed = parse_scalar(value)

        if key.startswith("rule."):
            _, rule_name, rule_field = key.split(".", 2)
            policy["rules"].setdefault(rule_name, {})[rule_field] = parsed
        else:
            policy[key] = parsed

    policy["loaded"] = True
    return policy

policy = load_policy(policy_path)

def rule(name, field, default=None):
    return (policy.get("rules") or {}).get(name, {}).get(field, default)

release_result = decision.get("releaseResult", "UNKNOWN")
execution_mode = decision.get("executionMode", policy.get("executionMode", "advisory_only"))
requires_human_approval = bool(decision.get("requiresHumanApproval", False))

agent_action = decision.get("agentAction") or {}
action_type = agent_action.get("type", "UNKNOWN")
action_allowed_by_ai = bool(agent_action.get("allowed", False))
action_requires_approval = bool(agent_action.get("requiresApproval", False))

guardrails = decision.get("guardrails") or {}
policy_auto_execute = bool(policy.get("autoExecute", False))
auto_execute = bool(guardrails.get("autoExecute", policy_auto_execute)) and policy_auto_execute
guardrail_execution_mode = guardrails.get("executionMode", policy.get("executionMode", execution_mode))

blocked_actions = set(policy.get("blockedActions") or []) | set(guardrails.get("blockedActions") or [])
dangerous_actions = set(policy.get("dangerousActions") or [])
allowed_actions = set(guardrails.get("allowedActions") or policy.get("allowedActions") or [])

matched_rules = []

if action_type in blocked_actions:
    policy_decision = "BLOCKED"
    final_action = "NONE"
    reason = f"{action_type} is blocked by guardrails"
    matched_rules.append("action_explicitly_blocked_by_guardrails")

elif allowed_actions and action_type not in allowed_actions:
    policy_decision = "BLOCKED"
    final_action = "NONE"
    reason = f"{action_type} is not in allowedActions"
    matched_rules.append("action_not_listed_in_allowed_actions")

elif action_type in dangerous_actions:
    policy_decision = "BLOCKED"
    final_action = "NONE"
    reason = f"{action_type} is blocked by default safety policy"
    matched_rules.append("dangerous_action_blocked_by_default")

elif release_result == "PASS" and action_type == "NOOP":
    policy_decision = rule("pass", "policyDecision", "ALLOW")
    final_action = rule("pass", "finalAction", "NOOP")
    reason = rule("pass", "reason", "Release passed and no action is required")
    matched_rules.append(rule("pass", "matchedRule", "pass_release_no_action"))

elif release_result == "FAIL_BY_MULTIPLE_SLO" and action_type == "STOP_PROMOTION":
    policy_decision = rule("multipleSlo", "policyDecision", "ALLOW_ADVISORY_ONLY")
    final_action = rule("multipleSlo", "finalAction", "STOP_PROMOTION")
    reason = rule("multipleSlo", "reason", "Multiple SLO gates failed; action is advisory only and requires human approval")
    matched_rules.append(rule("multipleSlo", "matchedRule", "multiple_slo_failure_requires_human_approval"))
    requires_human_approval = bool(rule("multipleSlo", "requiresHumanApproval", True))

elif release_result.startswith("FAIL_") and action_type == "STOP_PROMOTION":
    policy_decision = rule("failedStopPromotion", "policyDecision", "ALLOW_ADVISORY_ONLY")
    final_action = rule("failedStopPromotion", "finalAction", "STOP_PROMOTION")
    reason = rule("failedStopPromotion", "reason", "Release failed; stop promotion is advisory only and requires human approval")
    matched_rules.append(rule("failedStopPromotion", "matchedRule", "failed_release_stop_promotion_requires_human_approval"))
    requires_human_approval = bool(rule("failedStopPromotion", "requiresHumanApproval", True))

elif release_result == "IN_PROGRESS":
    policy_decision = rule("inProgress", "policyDecision", "ALLOW_ADVISORY_ONLY")
    final_action = action_type if action_type != "UNKNOWN" else rule("inProgress", "defaultFinalAction", "WAIT")
    reason = rule("inProgress", "reason", "Release is still in progress; policy remains advisory only")
    matched_rules.append(rule("inProgress", "matchedRule", "release_in_progress_advisory_only"))

else:
    policy_decision = rule("fallback", "policyDecision", "ALLOW_ADVISORY_ONLY")
    final_action = action_type if action_allowed_by_ai else "NONE"
    reason = rule("fallback", "reason", "No specific policy rule matched; fallback to advisory-only mode")
    matched_rules.append(rule("fallback", "matchedRule", "fallback_advisory_only"))

if not auto_execute:
    matched_rules.append(rule("autoExecuteDisabled", "matchedRule", "auto_execute_disabled"))

if guardrail_execution_mode == "advisory_only":
    matched_rules.append(rule("advisoryOnly", "matchedRule", "guardrail_advisory_only"))

policy_output = {
    "schemaVersion": "release.policy.evaluator/v1alpha1",
    "sourceDecisionFile": str(input_path),
    "policyDecision": policy_decision,
    "finalAction": final_action,
    "executionMode": guardrail_execution_mode,
    "requiresHumanApproval": requires_human_approval or action_requires_approval,
    "reason": reason,
    "matchedRules": matched_rules,
    "inputSummary": {
        "releaseResult": release_result,
        "agentActionType": action_type,
        "agentActionAllowed": action_allowed_by_ai,
        "agentActionRequiresApproval": action_requires_approval,
        "autoExecute": auto_execute,
    },
    "policyRef": {
        "file": str(policy_path),
        "loaded": bool(policy.get("loaded", False)),
        "schemaVersion": policy.get("schemaVersion"),
    },
}

output_path.parent.mkdir(parents=True, exist_ok=True)
with output_path.open("w", encoding="utf-8") as f:
    json.dump(policy_output, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"Wrote policy decision: {output_path}")
PY

cat "$OUTPUT_FILE"
