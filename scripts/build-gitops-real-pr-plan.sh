#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE="${1:-}"
REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"

if [ -z "$INPUT_FILE" ]; then
  INPUT_FILE="$(ls -t "$REPORT_DIR"/gitops-adapter-provider-result-*.json 2>/dev/null | grep -v latest | head -1 || true)"
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
  echo "ERROR: provider result file not found: ${INPUT_FILE:-empty}" >&2
  exit 1
fi

python3 - "$INPUT_FILE" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

input_path = Path(sys.argv[1])
data = json.loads(input_path.read_text(encoding="utf-8-sig"))

provider_result = data.get("providerResult") or {}
guardrails = data.get("guardrails") or {}
release = data.get("release") or {}

release_id = release.get("releaseId") or input_path.stem.replace("gitops-adapter-provider-result-", "")
package_dir = Path(provider_result.get("packageDir") or "")
package_manifest_path = Path(provider_result.get("packageManifestPath") or "")

package_manifest: dict[str, Any] = {}
commit_payload: dict[str, Any] = {}

if package_manifest_path.exists():
    package_manifest = json.loads(package_manifest_path.read_text(encoding="utf-8-sig"))
    commit_payload_path = Path(package_manifest.get("commitPayloadPath") or "")
    if commit_payload_path.exists():
        commit_payload = json.loads(commit_payload_path.read_text(encoding="utf-8-sig"))

branch_name = provider_result.get("branchName") or package_manifest.get("branchName") or commit_payload.get("branchName")
commit_message = commit_payload.get("commitMessage")
pr_title = commit_payload.get("pullRequestTitle") or provider_result.get("pullRequestTitle")
patch_entries = commit_payload.get("patchEntries") or []
payload_status = package_manifest.get("payloadStatus") or provider_result.get("resultStatus")

reasons: list[str] = []

if payload_status not in {"PAYLOAD_READY", "PROVIDER_RESULT_READY"}:
    reasons.append(f"payload/result status is not actionable: {payload_status}")

if not branch_name or str(branch_name).strip().lower() in {"unknown", "null", "none"}:
    reasons.append("branchName is missing or unknown")

if not commit_message:
    reasons.append("commitMessage is missing")

if not pr_title or pr_title == "No GitOps PR required":
    reasons.append("pullRequestTitle indicates no PR is required")

if not isinstance(patch_entries, list) or len(patch_entries) == 0:
    reasons.append("patchEntries is empty")

if guardrails.get("doesNotCommit") is True:
    reasons.append("guardrail doesNotCommit=true")

if guardrails.get("doesNotPush") is True:
    reasons.append("guardrail doesNotPush=true")

if guardrails.get("doesNotCreatePullRequest") is True:
    reasons.append("guardrail doesNotCreatePullRequest=true")

plan_status = "READY_FOR_REAL_PR" if not reasons else "BLOCKED_NO_ACTIONABLE_PR"

out_dir = input_path.parent
output = out_dir / f"gitops-real-pr-plan-{release_id}.json"
latest = out_dir / "gitops-real-pr-plan-latest.json"

plan = {
    "schemaVersion": "gitops.real.pr.plan/v1alpha1",
    "gitopsRealPRPlanId": f"gprplan-{release_id}",
    "generatedBy": "build-gitops-real-pr-plan.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "real_gitops_pr_preflight_plan",
    "release": release,
    "inputs": {
        "gitopsAdapterProviderResult": str(input_path),
        "packageDir": str(package_dir) if package_dir else None,
        "packageManifestPath": str(package_manifest_path) if package_manifest_path else None,
    },
    "plan": {
        "planStatus": plan_status,
        "providerType": provider_result.get("providerType"),
        "branchName": branch_name,
        "commitMessage": commit_message,
        "pullRequestTitle": pr_title,
        "patchEntryCount": len(patch_entries) if isinstance(patch_entries, list) else 0,
        "blockedReasons": reasons,
        "nextStep": (
            "Proceed to isolated git workspace materialization."
            if plan_status == "READY_FOR_REAL_PR"
            else "Do not create a real PR for this provider result."
        ),
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotCallExternalGitProvider": True,
        "doesNotModifyKubernetes": True,
        "derivedFromGitopsAdapterProviderResult": guardrails,
    },
}

text = json.dumps(plan, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
