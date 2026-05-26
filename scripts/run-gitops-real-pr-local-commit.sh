#!/usr/bin/env bash
set -euo pipefail

MATERIALIZATION_JSON="${1:-}"

if [ -z "$MATERIALIZATION_JSON" ] || [ ! -f "$MATERIALIZATION_JSON" ]; then
  echo "ERROR: materialization json not found: ${MATERIALIZATION_JSON:-empty}" >&2
  exit 1
fi

python3 - "$MATERIALIZATION_JSON" <<'PY'
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

mat_path = Path(sys.argv[1])
mat = json.loads(mat_path.read_text(encoding="utf-8-sig"))

release = mat.get("release") or {}
inputs = mat.get("inputs") or {}
m = mat.get("materialization") or {}

repo_dir = Path(inputs["repoDir"])
commit_payload_path = Path(inputs["commitPayloadPath"])

payload = json.loads(commit_payload_path.read_text(encoding="utf-8-sig"))
target_repository = mat.get("targetRepository") or payload.get("targetRepository") or {}
commit_message = payload.get("commitMessage")

if not commit_message:
    raise SystemExit("ERROR: commitMessage is missing")

status_before = subprocess.check_output(
    ["git", "-C", str(repo_dir), "status", "--short"],
    text=True,
).splitlines()

if not status_before:
    raise SystemExit("ERROR: no git changes to commit")

subprocess.check_call(["git", "-C", str(repo_dir), "add", "."])
subprocess.check_call(["git", "-C", str(repo_dir), "commit", "-m", commit_message])

commit_sha = subprocess.check_output(
    ["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
    text=True,
).strip()

branch = subprocess.check_output(
    ["git", "-C", str(repo_dir), "branch", "--show-current"],
    text=True,
).strip()

status_after = subprocess.check_output(
    ["git", "-C", str(repo_dir), "status", "--short"],
    text=True,
).splitlines()

release_id = release.get("releaseId") or mat_path.stem.replace("gitops-real-pr-materialization-", "")

out = {
    "schemaVersion": "gitops.real.pr.local.commit/v1alpha1",
    "gitopsRealPRLocalCommitId": "gprcommit-" + release_id,
    "generatedBy": "run-gitops-real-pr-local-commit.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_local_commit",
    "release": release,
    "inputs": {
        "gitopsRealPRMaterialization": str(mat_path),
        "repoDir": str(repo_dir),
        "commitPayloadPath": str(commit_payload_path)
    },
    "targetRepository": target_repository,
    "localCommit": {
        "commitStatus": "LOCAL_COMMIT_CREATED",
        "branchName": branch,
        "commitSha": commit_sha,
        "commitMessage": commit_message,
        "gitStatusBefore": status_before,
        "gitStatusAfter": status_after
    },
    "guardrails": {
        "readOnly": False,
        "dryRunOnly": False,
        "willExecute": False,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = mat_path.parent / f"gitops-real-pr-local-commit-{release_id}.json"
latest = mat_path.parent / "gitops-real-pr-local-commit-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
