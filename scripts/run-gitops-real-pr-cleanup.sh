#!/usr/bin/env bash
set -euo pipefail

PR_CREATE_JSON="${1:-}"

if [ "${S_SENTINEL_ALLOW_GITHUB_WRITE:-false}" != "true" ]; then
  echo "ERROR: set S_SENTINEL_ALLOW_GITHUB_WRITE=true to cleanup a real GitHub PR" >&2
  exit 1
fi

if [ "${S_SENTINEL_GITHUB_WRITE_OPERATION:-}" != "cleanup-pr" ]; then
  echo "ERROR: set S_SENTINEL_GITHUB_WRITE_OPERATION=cleanup-pr to cleanup a real GitHub PR" >&2
  exit 1
fi

if [ -z "$PR_CREATE_JSON" ] || [ ! -f "$PR_CREATE_JSON" ]; then
  echo "ERROR: PR create json not found: ${PR_CREATE_JSON:-empty}" >&2
  exit 1
fi

python3 - "$PR_CREATE_JSON" <<'PY'
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

create_path = Path(sys.argv[1])
data = json.loads(create_path.read_text(encoding="utf-8-sig"))

release = data.get("release") or {}
inputs = data.get("inputs") or {}
pr = data.get("pullRequest") or {}
target_repository = data.get("targetRepository") or {}
write_gate = {
    "enabled": True,
    "allowEnv": "S_SENTINEL_ALLOW_GITHUB_WRITE",
    "allowValue": "true",
    "operationEnv": "S_SENTINEL_GITHUB_WRITE_OPERATION",
    "requiredOperation": "cleanup-pr",
    "operation": os.environ.get("S_SENTINEL_GITHUB_WRITE_OPERATION"),
}

repo_dir = Path(inputs["repoDir"])
number = pr.get("number")
branch = pr.get("headRefName")

if not number:
    raise SystemExit("ERROR: PR number is missing")

if not branch:
    raise SystemExit("ERROR: PR headRefName is missing")

subprocess.run(
    [
        "gh", "pr", "close", str(number),
        "--comment", "Closing S Sentinel controlled GitOps PR smoke test. The PR creation flow has been verified.",
    ],
    cwd=repo_dir,
    text=True,
    check=False,
)

subprocess.run(
    ["git", "-C", str(repo_dir), "push", "origin", "--delete", branch],
    text=True,
    check=False,
)

pr_after = json.loads(subprocess.check_output(
    ["gh", "pr", "view", str(number), "--json", "number,title,state,url,headRefName,baseRefName"],
    cwd=repo_dir,
    text=True,
))

remote = subprocess.check_output(
    ["git", "-C", str(repo_dir), "ls-remote", "--heads", "origin", branch],
    text=True,
).splitlines()

release_id = release.get("releaseId") or create_path.stem.replace("gitops-real-pr-create-", "")

out = {
    "schemaVersion": "gitops.real.pr.cleanup/v1alpha1",
    "gitopsRealPRCleanupId": "gprcleanup-" + release_id,
    "generatedBy": "run-gitops-real-pr-cleanup.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_cleanup",
    "release": release,
    "inputs": {
        "gitopsRealPRCreate": str(create_path),
        "repoDir": str(repo_dir)
    },
    "targetRepository": target_repository,
    "writeGate": write_gate,
    "cleanup": {
        "cleanupStatus": "CLEANED_UP" if pr_after.get("state") == "CLOSED" and not remote else "NEEDS_ATTENTION",
        "pullRequest": pr_after,
        "remoteBranchExists": bool(remote),
        "remoteHeads": remote
    },
    "guardrails": {
        "readOnly": False,
        "dryRunOnly": False,
        "willExecute": True,
        "didClosePullRequest": True,
        "didDeleteRemoteBranch": True,
        "doesNotCommit": True,
        "doesNotCreatePullRequest": True,
        "doesNotMergePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = create_path.parent / f"gitops-real-pr-cleanup-{release_id}.json"
latest = create_path.parent / "gitops-real-pr-cleanup-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
