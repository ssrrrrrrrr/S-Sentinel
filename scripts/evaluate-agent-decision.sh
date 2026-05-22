#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
POLICY_FILE="${RELEASE_POLICY_FILE:-policy/release-policy.yaml}"

usage() {
  cat <<'USAGE'
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

python3 - "$INPUT_FILE" "$OUTPUT_FILE" "$POLICY_FILE" <<'PY_EVAL'
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
policy_path = Path(sys.argv[3])

decision = json.loads(input_path.read_text(encoding="utf-8"))

def parse_scalar(value: str) -> Any:
    value = value.strip().strip('"').strip("'")
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    return value

def load_policy(path: Path) -> dict[str, Any]:
    policy: dict[str, Any] = {
        "executionMode": "advisory_only",
        "autoExecute": False,
        "blockedActions": [],
        "allowedActions": [],
        "dangerousActions": [
            "ROLLBACK",
            "PROMOTE",
            "DELETE_RESOURCE",
            "PATCH_GITOPS",
            "PATCH_RESOURCE",
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

        if key.startswith("rule."):
            _, rule_name, rule_field = key.split(".", 2)
            policy["rules"].setdefault(rule_name, {})[rule_field] = parse_scalar(value)
        else:
            policy[key] = parse_scalar(value)

    policy["loaded"] = True
    return policy

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

def first_non_empty(*values: Any) -> Any:
    for value in values:
        if value not in (None, ""):
            return value
    return None

def release_id_from_ai_decision(path: Path) -> str | None:
    base = path.name
    if base.startswith("ai-decision-") and base.endswith(".json"):
        return base[len("ai-decision-"):-len(".json")]
    return None

def policy_decision_id(path: Path) -> str:
    release_id = release_id_from_ai_decision(path) or path.stem
    return f"pd-{release_id}"

def load_optional_json_path(ref: Any, base_path: Path) -> dict[str, Any]:
    if not ref:
        return {}
    raw = Path(str(ref))
    candidates: list[Path] = []
    if raw.is_absolute():
        candidates.append(raw)
    candidates.extend([
        base_path.parent / raw,
        base_path.parent / raw.name,
        Path.cwd() / raw,
        raw,
    ])
    for candidate in candidates:
        try:
            if candidate.exists() and candidate.is_file():
                data = json.loads(candidate.read_text(encoding="utf-8-sig"))
                return data if isinstance(data, dict) else {}
        except Exception:
            continue
    return {}

policy = load_policy(policy_path)

release_result = str(decision.get("releaseResult") or "UNKNOWN")
execution_mode = str(decision.get("executionMode") or policy.get("executionMode") or "advisory_only")

agent_action = as_dict(decision.get("agentAction"))
guardrails = as_dict(decision.get("guardrails"))
evidence = as_dict(decision.get("evidence"))

signed_release_gate_ref = as_dict(first_non_empty(
    decision.get("signedReleaseGateRef"),
    evidence.get("signedReleaseGateRef"),
))
signed_release_gate = as_dict(first_non_empty(
    decision.get("signedReleaseGate"),
    evidence.get("signedReleaseGate"),
))

if not signed_release_gate:
    signed_release_gate = load_optional_json_path(
        first_non_empty(
            signed_release_gate_ref.get("file"),
            signed_release_gate_ref.get("json"),
            signed_release_gate_ref.get("source"),
        ),
        input_path,
    )

signed_gate_decision_obj = as_dict(signed_release_gate.get("decision"))
signed_gate_risk = as_dict(signed_release_gate.get("risk"))
signed_gate_decision = nullable_string(signed_gate_decision_obj.get("decision"))
signed_gate_allowed = signed_gate_decision_obj.get("allowed")
signed_gate_allowed_bool = bool(signed_gate_allowed) if signed_gate_allowed is not None else None
signed_gate_requires_approval = bool(signed_gate_decision_obj.get("requiresHumanApproval", False))
signed_gate_blocking_reasons = [str(x) for x in as_list(signed_gate_decision_obj.get("blockingReasons")) if str(x)]
signed_gate_warning_reasons = [str(x) for x in as_list(signed_gate_decision_obj.get("warningReasons")) if str(x)]

requested_action = str(agent_action.get("type") or decision.get("recommendedAction") or "UNKNOWN")
agent_action_allowed = bool(agent_action.get("allowed", False))
agent_action_requires_approval = bool(agent_action.get("requiresApproval", False))

policy_auto_execute = bool(policy.get("autoExecute", False))
auto_execute = bool(guardrails.get("autoExecute", policy_auto_execute)) and policy_auto_execute
guardrail_execution_mode = str(guardrails.get("executionMode") or execution_mode)

blocked_actions = set(as_list(policy.get("blockedActions"))) | set(as_list(guardrails.get("blockedActions")))
allowed_actions = set(as_list(guardrails.get("allowedActions") or policy.get("allowedActions") or []))
dangerous_actions = set(as_list(policy.get("dangerousActions")))

strategy_failure_policy = as_dict(first_non_empty(
    decision.get("strategyFailurePolicy"),
    evidence.get("strategyFailurePolicy"),
))
strategy_promotion_policy = as_dict(first_non_empty(
    decision.get("strategyPromotionPolicy"),
    evidence.get("strategyPromotionPolicy"),
))

strategy_id = first_non_empty(decision.get("strategyId"), evidence.get("strategyId"))
strategy_type = first_non_empty(decision.get("strategyType"), evidence.get("strategyType"))

on_slo_failure = nullable_string(strategy_failure_policy.get("onSLOFailure"))
on_analysis_error = nullable_string(strategy_failure_policy.get("onAnalysisError"))
on_insufficient_traffic = nullable_string(strategy_failure_policy.get("onInsufficientTraffic"))
rollback_allowed = strategy_failure_policy.get("rollbackAllowed")
auto_promotion_enabled = strategy_promotion_policy.get("autoPromotionEnabled")
strategy_requires_human_approval = strategy_promotion_policy.get("requiresHumanApproval")
final_promotion_mode = nullable_string(strategy_promotion_policy.get("finalPromotionMode"))

rollback_allowed = bool(rollback_allowed) if rollback_allowed is not None else False
auto_promotion_enabled = bool(auto_promotion_enabled) if auto_promotion_enabled is not None else False
strategy_requires_human_approval = bool(strategy_requires_human_approval) if strategy_requires_human_approval is not None else False

allowed = False
policy_decision = "DENY"
final_action = "UNKNOWN"
reason = "Policy Guard denied the requested action by default"
matched_rules: list[str] = []
denied_reasons: list[str] = []
approval_required_reasons: list[str] = []

VALID_FINAL_ACTIONS = {"NOOP", "STOP_PROMOTION", "ROLLBACK", "PROMOTE", "INVESTIGATE", "UNKNOWN"}

def set_allow(action: str, rule_name: str, why: str, decision_value: str = "ALLOW_ADVISORY_ONLY") -> None:
    global allowed, policy_decision, final_action, reason
    allowed = True
    policy_decision = decision_value
    final_action = action if action in VALID_FINAL_ACTIONS else "UNKNOWN"
    reason = why
    matched_rules.append(rule_name)

def set_approval(action: str, rule_name: str, why: str, approval_reason: str) -> None:
    set_allow(action, rule_name, why, "REQUIRE_HUMAN_APPROVAL")
    approval_required_reasons.append(approval_reason)

def set_deny(action: str, rule_name: str, why: str) -> None:
    global allowed, policy_decision, final_action, reason
    allowed = False
    policy_decision = "DENY"
    final_action = action if action in VALID_FINAL_ACTIONS else "UNKNOWN"
    reason = why
    matched_rules.append(rule_name)
    denied_reasons.append(why)

if requested_action in blocked_actions:
    set_deny(requested_action, "action_explicitly_blocked_by_guardrails", f"{requested_action} is blocked by guardrails")

elif allowed_actions and requested_action not in allowed_actions:
    set_deny(requested_action, "action_not_listed_in_allowed_actions", f"{requested_action} is not listed in allowedActions")

elif requested_action in dangerous_actions and requested_action not in {"ROLLBACK", "PROMOTE"}:
    set_deny(requested_action, "dangerous_action_blocked_by_default", f"{requested_action} is blocked by default safety policy")

elif release_result == "PASS" and requested_action in {"NOOP", "OBSERVE"}:
    set_allow("NOOP", "pass_release_no_action", "Release passed and the requested action is observational")

elif release_result == "PASS" and requested_action == "PROMOTE":
    if auto_promotion_enabled:
        if strategy_requires_human_approval:
            set_approval(
                "PROMOTE",
                "pass_promote_requires_human_approval_by_strategy",
                "Release passed, but strategy requires human approval before promotion",
                "strategy_promotion_policy_requires_human_approval",
            )
        else:
            set_allow("PROMOTE", "pass_auto_promote_allowed_by_strategy", "Release passed and strategy allows auto promotion")
    else:
        set_deny("PROMOTE", "promote_denied_by_strategy_auto_promotion_disabled", "Promotion is denied because strategy autoPromotionEnabled is false")

elif release_result == "FAIL_BY_REQUEST_COUNT" and requested_action == "RETRY_WITH_MORE_TRAFFIC":
    if on_insufficient_traffic == "retry_with_more_traffic":
        set_allow("NOOP", "insufficient_traffic_retry_observation_allowed_by_strategy", "Insufficient canary traffic may be retried with more traffic; no direct execution is performed")
    else:
        set_deny("NOOP", "insufficient_traffic_retry_denied_by_strategy", "Retry with more traffic is not allowed by strategy failure policy")

elif release_result in {"FAIL_BY_ERROR_RATE", "FAIL_BY_P95_LATENCY", "FAIL_BY_MULTIPLE_SLO"} and requested_action == "STOP_PROMOTION":
    if on_slo_failure in {None, "", "stop_promotion"}:
        set_approval(
            "STOP_PROMOTION",
            "slo_failure_stop_promotion_allowed_by_strategy",
            "SLO failure matches strategy failure policy stop_promotion; action remains advisory and requires approval",
            "slo_failure_requires_human_approval",
        )
    else:
        set_deny("STOP_PROMOTION", "slo_failure_stop_promotion_denied_by_strategy", f"Strategy onSLOFailure is {on_slo_failure}, not stop_promotion")

elif requested_action == "ROLLBACK":
    if rollback_allowed:
        set_approval(
            "ROLLBACK",
            "rollback_allowed_by_strategy_but_requires_human_approval",
            "Rollback is allowed by strategy but must remain policy-bound and human-approved",
            "rollback_is_high_risk_action",
        )
    else:
        set_deny("ROLLBACK", "rollback_denied_by_strategy", "Rollback is denied because strategy rollbackAllowed is false")

elif requested_action == "PROMOTE":
    set_deny("PROMOTE", "promote_denied_unless_release_passed_and_strategy_allows", "Promotion is denied unless releaseResult is PASS and strategy allows promotion")

elif release_result in {"FAIL_BY_ROLLOUT_ABORT", "FAIL_BY_ROLLOUT_DEGRADED"} and requested_action in {"INVESTIGATE", "MANUAL_REVIEW"}:
    set_approval(
        "INVESTIGATE",
        "rollout_unhealthy_investigation_required",
        "Rollout is unhealthy; investigation is allowed as advisory-only action",
        "rollout_unhealthy_requires_human_review",
    )

elif release_result == "IN_PROGRESS" and requested_action in {"OBSERVE", "NOOP"}:
    set_allow("NOOP", "release_in_progress_observe_only", "Release is still in progress; observe-only action is allowed")

elif requested_action in {"MANUAL_REVIEW", "INVESTIGATE"}:
    set_approval(
        "INVESTIGATE",
        "fallback_manual_review_required",
        "No specific strategy-aware rule matched; manual review is required",
        "fallback_manual_review_required",
    )

else:
    set_deny(requested_action, "fallback_deny_unknown_or_unsafe_action", "No specific strategy-aware rule matched and the requested action is not safe")

signed_gate_summary = {
    "loaded": bool(signed_release_gate),
    "schemaVersion": signed_release_gate.get("schemaVersion"),
    "signedReleaseGateId": signed_release_gate.get("signedReleaseGateId"),
    "decision": signed_gate_decision,
    "allowed": signed_gate_allowed_bool,
    "requiresHumanApproval": signed_gate_requires_approval,
    "riskLevel": signed_gate_risk.get("riskLevel"),
    "riskScore": signed_gate_risk.get("riskScore"),
    "blockingReasons": signed_gate_blocking_reasons,
    "warningReasons": signed_gate_warning_reasons,
    "source": first_non_empty(
        signed_release_gate_ref.get("file"),
        signed_release_gate_ref.get("json"),
        signed_release_gate_ref.get("source"),
    ),
}

if signed_gate_decision == "BLOCK":
    gate_reason = "SignedReleaseGate blocked this release"
    if signed_gate_blocking_reasons:
        gate_reason = "; ".join(signed_gate_blocking_reasons)
    set_deny(
        final_action if final_action in VALID_FINAL_ACTIONS and final_action != "UNKNOWN" else requested_action,
        "signed_release_gate_blocked",
        gate_reason,
    )
    denied_reasons.extend(signed_gate_blocking_reasons)

elif signed_gate_decision == "REQUIRE_HUMAN_APPROVAL" and policy_decision != "DENY":
    policy_decision = "REQUIRE_HUMAN_APPROVAL"
    matched_rules.append("signed_release_gate_requires_human_approval")
    approval_required_reasons.append("signed_release_gate_requires_human_approval")
    approval_required_reasons.extend(signed_gate_warning_reasons)
    if signed_gate_warning_reasons:
        reason = "SignedReleaseGate requires human approval: " + "; ".join(signed_gate_warning_reasons)

if not auto_execute:
    matched_rules.append("auto_execute_disabled")

if guardrail_execution_mode == "advisory_only":
    matched_rules.append("guardrail_advisory_only")

if agent_action_requires_approval:
    approval_required_reasons.append("agent_action_requires_approval")

if strategy_requires_human_approval and allowed:
    approval_required_reasons.append("strategy_requires_human_approval")

approval_required_reasons = sorted(set(approval_required_reasons))
denied_reasons = sorted(set(denied_reasons))
matched_rules = list(dict.fromkeys(matched_rules))

requires_human_approval = bool(
    decision.get("requiresHumanApproval", False)
    or agent_action_requires_approval
    or signed_gate_decision == "REQUIRE_HUMAN_APPROVAL"
    or approval_required_reasons
)

if allowed and requires_human_approval and policy_decision == "ALLOW_ADVISORY_ONLY":
    policy_decision = "REQUIRE_HUMAN_APPROVAL"

if not allowed:
    requires_human_approval = False
    approval_required_reasons = []

policy_output = {
    "schemaVersion": "release.policy.evaluator/v1alpha1",
    "policyDecisionId": policy_decision_id(input_path),
    "sourceDecisionFile": str(input_path),
    "releaseId": release_id_from_ai_decision(input_path),
    "evidenceId": nullable_string(decision.get("evidenceId")),
    "service": nullable_string(first_non_empty(decision.get("service"), evidence.get("service"))),
    "env": nullable_string(first_non_empty(decision.get("env"), evidence.get("env"))),
    "sloId": nullable_string(first_non_empty(decision.get("sloId"), evidence.get("sloId"))),
    "strategyId": nullable_string(strategy_id),
    "policyDecision": policy_decision,
    "requestedAction": requested_action,
    "allowed": allowed,
    "finalAction": final_action,
    "executionMode": guardrail_execution_mode,
    "requiresHumanApproval": requires_human_approval,
    "reason": reason,
    "deniedReasons": denied_reasons,
    "approvalRequiredReasons": approval_required_reasons,
    "matchedRules": matched_rules,
    "signedReleaseGate": signed_gate_summary,
    "inputSummary": {
        "releaseResult": release_result,
        "agentActionType": requested_action,
        "agentActionAllowed": agent_action_allowed,
        "agentActionRequiresApproval": agent_action_requires_approval,
        "autoExecute": auto_execute,
        "signedReleaseGateDecision": signed_gate_decision,
        "signedReleaseGateAllowed": signed_gate_allowed_bool,
    },
    "strategyPolicy": {
        "strategyId": nullable_string(strategy_id),
        "strategyType": nullable_string(strategy_type),
        "onSLOFailure": on_slo_failure,
        "onAnalysisError": on_analysis_error,
        "onInsufficientTraffic": on_insufficient_traffic,
        "rollbackAllowed": rollback_allowed,
        "autoPromotionEnabled": auto_promotion_enabled,
        "requiresHumanApproval": strategy_requires_human_approval,
        "finalPromotionMode": final_promotion_mode,
    },
    "safety": {
        "readOnly": True,
        "willExecute": False,
        "autoExecute": auto_execute,
        "advisoryOnly": guardrail_execution_mode == "advisory_only",
        "dangerousAction": requested_action in dangerous_actions,
        "strategyBound": bool(strategy_id),
    },
    "policyRef": {
        "file": str(policy_path),
        "loaded": bool(policy.get("loaded", False)),
        "schemaVersion": policy.get("schemaVersion"),
    },
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(policy_output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print(f"Wrote policy decision: {output_path}")
PY_EVAL

validate_generated_release_contract "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
