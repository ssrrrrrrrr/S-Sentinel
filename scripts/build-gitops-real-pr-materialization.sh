#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_JSON="${1:-}"

if [ -z "$WORKSPACE_JSON" ] || [ ! -f "$WORKSPACE_JSON" ]; then
  echo "ERROR: workspace json not found: ${WORKSPACE_JSON:-empty}" >&2
  exit 1
fi

python3 - "$WORKSPACE_JSON" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

workspace_json = Path(sys.argv[1])
data = json.loads(workspace_json.read_text(encoding="utf-8-sig"))

release = data.get("release") or {}
workspace = data.get("workspace") or {}

release_id = release.get("releaseId") or workspace_json.stem.replace("gitops-real-pr-workspace-", "")
workspace_dir = Path(workspace["workspaceDir"])
repo_dir = workspace_dir / "repo"
commit_payload_path = workspace_dir / "provider-package" / "commit-payload.json"

commit_payload = json.loads(commit_payload_path.read_text(encoding="utf-8-sig"))
patch_entries = commit_payload.get("patchEntries") or []

materializable = []
blocked = []

for entry in patch_entries:
    target = entry.get("targetRef") or entry.get("targetPath")
    has_inline = bool(entry.get("content") or entry.get("renderedContent"))
    has_source = bool(entry.get("sourcePath") or entry.get("renderedFilePath") or entry.get("filePath"))

    if target and (has_inline or has_source):
        materializable.append(entry)
    else:
        blocked.append({
            "entryId": entry.get("entryId"),
            "targetRef": target,
            "reason": "missing content/sourcePath/renderedFilePath"
        })

status = "READY_TO_MATERIALIZE" if materializable else "BLOCKED_NO_MATERIALIZABLE_FILES"

out = {
    "schemaVersion": "gitops.real.pr.materialization/v1alpha1",
    "gitopsRealPRMaterializationId": "gprmat-" + release_id,
    "generatedBy": "build-gitops-real-pr-materialization.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "real_gitops_pr_materialization_preflight",
    "release": release,
    "inputs": {
        "gitopsRealPRWorkspace": str(workspace_json),
        "workspaceDir": str(workspace_dir),
        "repoDir": str(repo_dir),
        "commitPayloadPath": str(commit_payload_path)
    },
    "materialization": {
        "materializationStatus": status,
        "branchName": commit_payload.get("branchName"),
        "commitMessage": commit_payload.get("commitMessage"),
        "pullRequestTitle": commit_payload.get("pullRequestTitle"),
        "patchEntryCount": len(patch_entries),
        "materializableFileCount": len(materializable),
        "blockedEntryCount": len(blocked),
        "blockedEntries": blocked,
        "nextStep": "Materialize files into isolated repo." if materializable else "Do not write files until patch entries include content or source paths."
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = workspace_json.parent / f"gitops-real-pr-materialization-{release_id}.json"
latest = workspace_json.parent / "gitops-real-pr-materialization-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
