#!/usr/bin/env bash
set -euo pipefail

PR_PREFLIGHT_JSON="${1:-}"

if [ "${S_SENTINEL_ALLOW_GITHUB_WRITE:-false}" != "true" ]; then
  echo "ERROR: set S_SENTINEL_ALLOW_GITHUB_WRITE=true to create a real GitHub PR" >&2
  exit 1
fi

if [ "${S_SENTINEL_GITHUB_WRITE_OPERATION:-}" != "create-pr" ]; then
  echo "ERROR: set S_SENTINEL_GITHUB_WRITE_OPERATION=create-pr to create a real GitHub PR" >&2
  exit 1
fi

if [ -z "$PR_PREFLIGHT_JSON" ] || [ ! -f "$PR_PREFLIGHT_JSON" ]; then
  echo "ERROR: PR preflight json not found: ${PR_PREFLIGHT_JSON:-empty}" >&2
  exit 1
fi

python3 - "$PR_PREFLIGHT_JSON" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

pf_path = Path(sys.argv[1])
pf = json.loads(pf_path.read_text(encoding="utf-8-sig"))

release = pf.get("release") or {}
inputs = pf.get("inputs") or {}
preflight = pf.get("prCreatePreflight") or {}
target_repository = pf.get("targetRepository") or {}

target_owner = target_repository.get("owner") or preflight.get("headOwner")
target_base_branch = target_repository.get("baseBranch") or preflight.get("baseBranch")

if not target_owner:
    raise SystemExit("ERROR: targetRepository.owner/headOwner is missing")

if not target_base_branch:
    raise SystemExit("ERROR: targetRepository.baseBranch is missing")

if preflight.get("preflightStatus") != "READY_TO_CREATE_PR":
    raise SystemExit("ERROR: PR preflight is not READY_TO_CREATE_PR")

repo_dir = Path(inputs["repoDir"])
branch = preflight["branchName"]
title = preflight["pullRequestTitle"]
body_path = Path(preflight["pullRequestBodyPath"])
if not body_path.is_absolute():
    body_path = (Path.cwd() / body_path).resolve()

if not body_path.exists():
    raise SystemExit(f"ERROR: PR body file not found: {body_path}")

existing = json.loads(subprocess.check_output(
    ["gh", "pr", "list", "--head", f"{target_owner}:{branch}", "--json", "number,title,state,url"],
    cwd=repo_dir,
    text=True,
))

if existing:
    raise SystemExit("ERROR: PR already exists for this branch")

pr_url = subprocess.check_output(
    [
        "gh", "pr", "create",
        "--base", target_base_branch,
        "--head", branch,
        "--title", title,
        "--body-file", str(body_path),
    ],
    cwd=repo_dir,
    text=True,
).strip()

pr = json.loads(subprocess.check_output(
    [
        "gh", "pr", "view", pr_url,
        "--json", "number,title,state,url,headRefName,baseRefName,author,createdAt,isDraft,mergeStateStatus",
    ],
    cwd=repo_dir,
    text=True,
))

release_id = release.get("releaseId") or pf_path.stem.replace("gitops-real-pr-create-preflight-", "")

out = {
    "schemaVersion": "gitops.real.pr.create/v1alpha1",
    "gitopsRealPRCreateId": "gprcreate-" + release_id,
    "generatedBy": "run-gitops-real-pr-create.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_create",
    "release": release,
    "inputs": {
        "gitopsRealPRCreatePreflight": str(pf_path),
        "repoDir": str(repo_dir),
        "pullRequestBodyPath": str(body_path)
    },
    "targetRepository": target_repository,
    "pullRequest": {
        "createStatus": "PULL_REQUEST_CREATED",
        "repo": preflight.get("repo"),
        "number": pr.get("number"),
        "title": pr.get("title"),
        "state": pr.get("state"),
        "url": pr.get("url"),
        "headRefName": pr.get("headRefName"),
        "baseRefName": pr.get("baseRefName"),
        "author": pr.get("author"),
        "isDraft": pr.get("isDraft"),
        "mergeStateStatus": pr.get("mergeStateStatus"),
        "createdAt": pr.get("createdAt")
    },
    "guardrails": {
        "readOnly": False,
        "dryRunOnly": False,
        "willExecute": True,
        "didCreatePullRequest": True,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotMergePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = pf_path.parent / f"gitops-real-pr-create-{release_id}.json"
latest = pf_path.parent / "gitops-real-pr-create-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
