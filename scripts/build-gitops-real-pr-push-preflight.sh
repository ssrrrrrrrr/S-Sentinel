#!/usr/bin/env bash
set -euo pipefail

LOCAL_COMMIT_JSON="${1:-}"

if [ -z "$LOCAL_COMMIT_JSON" ] || [ ! -f "$LOCAL_COMMIT_JSON" ]; then
  echo "ERROR: local commit json not found: ${LOCAL_COMMIT_JSON:-empty}" >&2
  exit 1
fi

python3 - "$LOCAL_COMMIT_JSON" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

commit_json = Path(sys.argv[1])
data = json.loads(commit_json.read_text(encoding="utf-8-sig"))

release = data.get("release") or {}
inputs = data.get("inputs") or {}
local_commit = data.get("localCommit") or {}

repo_dir = Path(inputs["repoDir"])
branch = local_commit.get("branchName")
commit_sha = local_commit.get("commitSha")

reasons = []

if not repo_dir.exists():
    reasons.append(f"repoDir does not exist: {repo_dir}")

if not branch:
    reasons.append("branchName is missing")

if not commit_sha:
    reasons.append("commitSha is missing")

current_branch = subprocess.check_output(
    ["git", "-C", str(repo_dir), "branch", "--show-current"],
    text=True,
).strip()

status = subprocess.check_output(
    ["git", "-C", str(repo_dir), "status", "--short"],
    text=True,
).splitlines()

head_sha = subprocess.check_output(
    ["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
    text=True,
).strip()

remote_heads = subprocess.check_output(
    ["git", "-C", str(repo_dir), "ls-remote", "--heads", "origin", branch or ""],
    text=True,
).splitlines()

gh_status = subprocess.run(
    ["gh", "auth", "status"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)

if current_branch != branch:
    reasons.append(f"current branch mismatch: current={current_branch}, expected={branch}")

if head_sha != commit_sha:
    reasons.append(f"HEAD mismatch: head={head_sha}, expected={commit_sha}")

if status:
    reasons.append("repo has uncommitted changes")

if remote_heads:
    reasons.append("remote branch already exists")

if gh_status.returncode != 0:
    reasons.append("gh auth status failed")

preflight_status = "READY_TO_PUSH_BRANCH" if not reasons else "BLOCKED_BEFORE_PUSH"
release_id = release.get("releaseId") or commit_json.stem.replace("gitops-real-pr-local-commit-", "")

out = {
    "schemaVersion": "gitops.real.pr.push.preflight/v1alpha1",
    "gitopsRealPRPushPreflightId": "gprpushpf-" + release_id,
    "generatedBy": "build-gitops-real-pr-push-preflight.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_push_preflight",
    "release": release,
    "inputs": {
        "gitopsRealPRLocalCommit": str(commit_json),
        "repoDir": str(repo_dir)
    },
    "pushPreflight": {
        "preflightStatus": preflight_status,
        "branchName": branch,
        "commitSha": commit_sha,
        "currentBranch": current_branch,
        "headSha": head_sha,
        "gitStatusShort": status,
        "remoteBranchExists": bool(remote_heads),
        "blockedReasons": reasons,
        "nextStep": "Push local branch to origin only." if not reasons else "Do not push until blocked reasons are resolved."
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = commit_json.parent / f"gitops-real-pr-push-preflight-{release_id}.json"
latest = commit_json.parent / "gitops-real-pr-push-preflight-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
