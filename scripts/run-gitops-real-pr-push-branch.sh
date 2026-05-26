#!/usr/bin/env bash
set -euo pipefail

PUSH_PREFLIGHT_JSON="${1:-}"

if [ -z "$PUSH_PREFLIGHT_JSON" ] || [ ! -f "$PUSH_PREFLIGHT_JSON" ]; then
  echo "ERROR: push preflight json not found: ${PUSH_PREFLIGHT_JSON:-empty}" >&2
  exit 1
fi

python3 - "$PUSH_PREFLIGHT_JSON" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

pf_path = Path(sys.argv[1])
pf = json.loads(pf_path.read_text(encoding="utf-8-sig"))

release = pf.get("release") or {}
inputs = pf.get("inputs") or {}
push_pf = pf.get("pushPreflight") or {}
target_repository = pf.get("targetRepository") or {}

if push_pf.get("preflightStatus") != "READY_TO_PUSH_BRANCH":
    raise SystemExit("ERROR: push preflight is not READY_TO_PUSH_BRANCH")

repo_dir = Path(inputs["repoDir"])
branch = push_pf["branchName"]
commit_sha = push_pf["commitSha"]

subprocess.check_call(["git", "-C", str(repo_dir), "push", "-u", "origin", branch])

remote_heads = subprocess.check_output(
    ["git", "-C", str(repo_dir), "ls-remote", "--heads", "origin", branch],
    text=True,
).splitlines()

status_after = subprocess.check_output(
    ["git", "-C", str(repo_dir), "status", "--short"],
    text=True,
).splitlines()

release_id = release.get("releaseId") or pf_path.stem.replace("gitops-real-pr-push-preflight-", "")

out = {
    "schemaVersion": "gitops.real.pr.branch.push/v1alpha1",
    "gitopsRealPRBranchPushId": "gprpush-" + release_id,
    "generatedBy": "run-gitops-real-pr-push-branch.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_branch_push",
    "release": release,
    "inputs": {
        "gitopsRealPRPushPreflight": str(pf_path),
        "repoDir": str(repo_dir)
    },
    "targetRepository": target_repository,
    "branchPush": {
        "pushStatus": "BRANCH_PUSHED",
        "branchName": branch,
        "commitSha": commit_sha,
        "remoteBranchExists": bool(remote_heads),
        "remoteHeads": remote_heads,
        "gitStatusAfter": status_after,
        "nextStep": "Create pull request only after PR preflight passes."
    },
    "guardrails": {
        "readOnly": False,
        "dryRunOnly": False,
        "willExecute": False,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = pf_path.parent / f"gitops-real-pr-branch-push-{release_id}.json"
latest = pf_path.parent / "gitops-real-pr-branch-push-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
