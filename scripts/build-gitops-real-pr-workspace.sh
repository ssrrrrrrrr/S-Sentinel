#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE="${1:-}"
BASE_DIR="${GITOPS_REAL_PR_WORKSPACE_BASE_DIR:-/data/nfs/slo-rollout-watcher/gitops-pr-runs}"

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: plan file not found: ${PLAN_FILE:-empty}" >&2
  exit 1
fi

python3 - "$PLAN_FILE" "$BASE_DIR" <<'PY'
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

plan_path = Path(sys.argv[1])
base_dir = Path(sys.argv[2])

data = json.loads(plan_path.read_text(encoding="utf-8-sig"))
plan = data.get("plan") or {}
release = data.get("release") or {}
inputs = data.get("inputs") or {}

plan_id = data.get("gitopsRealPRPlanId") or plan_path.stem
release_id = release.get("releaseId") or plan_id.replace("gprplan-", "")
workspace_dir = base_dir / plan_id
package_src = Path(inputs.get("packageDir") or "")
package_dst = workspace_dir / "provider-package"

workspace_dir.mkdir(parents=True, exist_ok=True)

if package_dst.exists():
    shutil.rmtree(package_dst)

if package_src.exists():
    shutil.copytree(package_src, package_dst)
else:
    package_dst.mkdir(parents=True, exist_ok=True)

branch = plan.get("branchName") or "<missing-branch>"
commit = plan.get("commitMessage") or "<missing-commit-message>"
title = plan.get("pullRequestTitle") or "<missing-pr-title>"

preview = workspace_dir / "git-commands-preview.sh"
preview.write_text(f"""#!/usr/bin/env bash
set -euo pipefail

# Preview only. Do not execute automatically.

git clone https://github.com/ssrrrrrrrr/S-Sentinel.git repo
cd repo
git checkout -b {branch}
# materialize files from provider-package
git status --short
git add <materialized-files>
git commit -m {json.dumps(commit)}
git push origin {branch}
gh pr create --title {json.dumps(title)} --body-file <pull-request-body.md>
""", encoding="utf-8")
preview.chmod(0o755)

out = {
    "schemaVersion": "gitops.real.pr.workspace/v1alpha1",
    "gitopsRealPRWorkspaceId": "gprws-" + release_id,
    "generatedBy": "build-gitops-real-pr-workspace.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "real_gitops_pr_workspace_preview",
    "release": release,
    "inputs": {
        "gitopsRealPRPlan": str(plan_path),
        "packageDir": str(package_src) if package_src else None
    },
    "workspace": {
        "workspaceStatus": "WORKSPACE_PREPARED" if plan.get("planStatus") == "READY_FOR_REAL_PR" else "BLOCKED_BY_PLAN",
        "workspaceDir": str(workspace_dir),
        "providerPackageDir": str(package_dst),
        "gitCommandsPreviewPath": str(preview),
        "planStatus": plan.get("planStatus"),
        "branchName": plan.get("branchName"),
        "commitMessage": plan.get("commitMessage"),
        "pullRequestTitle": plan.get("pullRequestTitle")
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotClone": True,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotCallExternalGitProvider": True,
        "doesNotModifyKubernetes": True
    }
}

output = plan_path.parent / f"gitops-real-pr-workspace-{release_id}.json"
latest = plan_path.parent / "gitops-real-pr-workspace-latest.json"
text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")
print(output)
PY
