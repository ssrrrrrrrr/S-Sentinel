#!/usr/bin/env bash
set -euo pipefail

BRANCH_PUSH_JSON="${1:-}"

if [ -z "$BRANCH_PUSH_JSON" ] || [ ! -f "$BRANCH_PUSH_JSON" ]; then
  echo "ERROR: branch push json not found: ${BRANCH_PUSH_JSON:-empty}" >&2
  exit 1
fi

python3 - "$BRANCH_PUSH_JSON" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

push_path = Path(sys.argv[1])
push = json.loads(push_path.read_text(encoding="utf-8-sig"))

release = push.get("release") or {}
inputs = push.get("inputs") or {}
branch_push = push.get("branchPush") or {}

repo_dir = Path(inputs["repoDir"])
push_preflight_path = Path(inputs["gitopsRealPRPushPreflight"])
push_preflight = json.loads(push_preflight_path.read_text(encoding="utf-8-sig"))

local_commit_path = Path(push_preflight["inputs"]["gitopsRealPRLocalCommit"])
local_commit = json.loads(local_commit_path.read_text(encoding="utf-8-sig"))

commit_payload_path = Path(local_commit["inputs"]["commitPayloadPath"])
payload = json.loads(commit_payload_path.read_text(encoding="utf-8-sig"))

branch = branch_push.get("branchName")
commit_sha = branch_push.get("commitSha")
title = payload.get("pullRequestTitle")
commit_message = payload.get("commitMessage")

reasons = []

if branch_push.get("pushStatus") != "BRANCH_PUSHED":
    reasons.append("branch has not been pushed")

if not branch_push.get("remoteBranchExists"):
    reasons.append("remote branch does not exist")

if not branch:
    reasons.append("branchName is missing")

if not title:
    reasons.append("pullRequestTitle is missing")

gh_status = subprocess.run(
    ["gh", "auth", "status"],
    cwd=str(repo_dir),
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)

if gh_status.returncode != 0:
    reasons.append("gh auth status failed")

repo_info = subprocess.check_output(
    ["gh", "repo", "view", "--json", "owner,name"],
    cwd=str(repo_dir),
    text=True,
)
repo = json.loads(repo_info)
owner = repo["owner"]["login"]
name = repo["name"]

existing_raw = subprocess.check_output(
    ["gh", "pr", "list", "--head", f"{owner}:{branch}", "--json", "number,title,state,url"],
    cwd=str(repo_dir),
    text=True,
)
existing_prs = json.loads(existing_raw)

if existing_prs:
    reasons.append("pull request already exists for this branch")

body = payload.get("pullRequestBody")
if not body:
    body = f"""# S Sentinel GitOps PR

Release: `{release.get('releaseId')}`
Service: `{release.get('service')}`
Environment: `{release.get('env')}`
Action: `{release.get('finalAction')}`

Branch: `{branch}`
Commit: `{commit_sha}`

This PR was prepared by the S Sentinel controlled GitOps PR integration flow.

Guardrails:
- branch was created from an isolated workspace
- local commit was created before push
- Kubernetes was not modified by this flow
"""

body_path = push_path.parent / f"gitops-real-pr-body-{release.get('releaseId', 'unknown')}.md"
body_path.write_text(body, encoding="utf-8")

status = "READY_TO_CREATE_PR" if not reasons else "BLOCKED_BEFORE_PR_CREATE"
release_id = release.get("releaseId") or push_path.stem.replace("gitops-real-pr-branch-push-", "")

out = {
    "schemaVersion": "gitops.real.pr.create.preflight/v1alpha1",
    "gitopsRealPRCreatePreflightId": "gprprpf-" + release_id,
    "generatedBy": "build-gitops-real-pr-create-preflight.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_create_preflight",
    "release": release,
    "inputs": {
        "gitopsRealPRBranchPush": str(push_path),
        "repoDir": str(repo_dir),
        "commitPayloadPath": str(commit_payload_path)
    },
    "prCreatePreflight": {
        "preflightStatus": status,
        "repo": f"{owner}/{name}",
        "branchName": branch,
        "commitSha": commit_sha,
        "pullRequestTitle": title,
        "pullRequestBodyPath": str(body_path),
        "existingPullRequests": existing_prs,
        "blockedReasons": reasons,
        "nextStep": "Create pull request with gh pr create." if not reasons else "Do not create PR until blocked reasons are resolved."
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = push_path.parent / f"gitops-real-pr-create-preflight-{release_id}.json"
latest = push_path.parent / "gitops-real-pr-create-preflight-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
