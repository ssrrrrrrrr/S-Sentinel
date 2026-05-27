#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p .tmp

for action in pause resume promote abort rollback; do
  bash "scripts/test-runtime-action-execution-result-mock-${action}.sh" > ".tmp/test-canonical-summary-${action}.log"
done

python3 - <<'PY'
import json
from pathlib import Path

cases = {
    "pause": {
        "action": "PAUSE_ROLLOUT",
        "risk": "medium_high",
        "command": "kubectl_patch_rollout_spec_paused",
    },
    "resume": {
        "action": "RESUME_ROLLOUT",
        "risk": "medium_high",
        "command": "kubectl_patch_rollout_spec_paused_false",
    },
    "promote": {
        "action": "PROMOTE_ROLLOUT",
        "risk": "high",
        "command": "kubectl_argo_rollouts_promote",
    },
    "abort": {
        "action": "ABORT_ROLLOUT",
        "risk": "high",
        "command": "kubectl_argo_rollouts_abort",
    },
    "rollback": {
        "action": "ROLLBACK_ROLLOUT",
        "risk": "high",
        "command": "kubectl_argo_rollouts_undo_to_revision",
    },
}

for name, expected in cases.items():
    path = Path(f".tmp/test-runtime-action-execution-result-mock-{name}/runtime-action-execution-result-latest.json")
    data = json.loads(path.read_text(encoding="utf-8"))

    execution = data.get("executionSummary") or {}
    gate = data.get("gateSummary") or {}
    verification = data.get("verificationSummary") or {}
    risk = data.get("riskSummary") or {}

    assert execution["requestedAction"] == expected["action"], (name, execution)
    assert execution["didExecute"] is True, (name, execution)
    assert execution["verified"] is True, (name, execution)
    assert execution["commandMode"] == expected["command"], (name, execution)

    assert gate["overall"] == "EXECUTION_SUCCEEDED", (name, gate)
    assert gate["willExecute"] is True, (name, gate)

    assert verification["status"] == "VERIFIED", (name, verification)
    assert verification["actionVerified"] is True, (name, verification)

    assert risk["riskLevel"] == expected["risk"], (name, risk)
    assert risk["defaultOff"] is True, (name, risk)
    assert risk["mutatesGitOps"] is False, (name, risk)

print("PASS runtime action canonical summaries for all actions")
PY
