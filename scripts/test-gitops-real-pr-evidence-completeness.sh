#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "${S_SENTINEL_ALLOW_GITHUB_WRITE:-false}" = "true" ]; then
  echo "ERROR: evidence completeness test must not run with S_SENTINEL_ALLOW_GITHUB_WRITE=true" >&2
  exit 1
fi

export S_SENTINEL_ALLOW_GITHUB_WRITE=false

echo "===== locate complete local real-pr evidence chain ====="
LATEST_DIR="$(python3 - <<'PY2'
from pathlib import Path

for root in reversed(sorted(Path(".tmp").glob("test-gitops-real-pr-local-flow-*"))):
    run_id = root.name.replace("test-gitops-real-pr-local-flow-", "")
    release_id = "local-flow-" + run_id
    needed = [
        root / f"gitops-real-pr-plan-{release_id}.json",
        root / f"gitops-real-pr-workspace-{release_id}.json",
        root / f"gitops-real-pr-materialization-{release_id}.json",
        root / f"gitops-real-pr-file-materialization-{release_id}.json",
        root / f"gitops-real-pr-local-commit-{release_id}.json",
        root / f"gitops-real-pr-push-preflight-{release_id}.json",
    ]
    if all(p.exists() for p in needed):
        print(root)
        raise SystemExit(0)

raise SystemExit(1)
PY2
)" || true

if [ -z "$LATEST_DIR" ]; then
  echo "No complete existing local-flow evidence found; generating one with timeout."
  timeout 120s bash scripts/test-gitops-real-pr-local-flow.sh

  LATEST_DIR="$(python3 - <<'PY2'
from pathlib import Path

for root in reversed(sorted(Path(".tmp").glob("test-gitops-real-pr-local-flow-*"))):
    run_id = root.name.replace("test-gitops-real-pr-local-flow-", "")
    release_id = "local-flow-" + run_id
    needed = [
        root / f"gitops-real-pr-plan-{release_id}.json",
        root / f"gitops-real-pr-workspace-{release_id}.json",
        root / f"gitops-real-pr-materialization-{release_id}.json",
        root / f"gitops-real-pr-file-materialization-{release_id}.json",
        root / f"gitops-real-pr-local-commit-{release_id}.json",
        root / f"gitops-real-pr-push-preflight-{release_id}.json",
    ]
    if all(p.exists() for p in needed):
        print(root)
        raise SystemExit(0)

raise SystemExit(1)
PY2
)" || true
fi

if [ -z "$LATEST_DIR" ] || [ ! -d "$LATEST_DIR" ]; then
  echo "ERROR: complete local flow evidence dir not found" >&2
  exit 1
fi

echo "latestEvidenceDir=$LATEST_DIR"

python3 - "$LATEST_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
run_id = root.name.replace("test-gitops-real-pr-local-flow-", "")
release_id = "local-flow-" + run_id
branch = "ssentinel/local-flow-" + run_id

expected = [
    ("gitopsRealPRPlan", "gitopsRealPRPlanId", root / f"gitops-real-pr-plan-{release_id}.json"),
    ("gitopsRealPRWorkspace", "gitopsRealPRWorkspaceId", root / f"gitops-real-pr-workspace-{release_id}.json"),
    ("gitopsRealPRMaterialization", "gitopsRealPRMaterializationId", root / f"gitops-real-pr-materialization-{release_id}.json"),
    ("gitopsRealPRFileMaterialization", "gitopsRealPRFileMaterializationId", root / f"gitops-real-pr-file-materialization-{release_id}.json"),
    ("gitopsRealPRLocalCommit", "gitopsRealPRLocalCommitId", root / f"gitops-real-pr-local-commit-{release_id}.json"),
    ("gitopsRealPRPushPreflight", "gitopsRealPRPushPreflightId", root / f"gitops-real-pr-push-preflight-{release_id}.json"),
]

def walk(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k, v
            yield from walk(v)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)

def contains_pair(data, key, expected_value):
    return any(k == key and v == expected_value for k, v in walk(data))

for kind, id_key, path in expected:
    if not path.exists():
        raise SystemExit(f"missing {kind} evidence file: {path}")

    data = json.loads(path.read_text(encoding="utf-8-sig"))

    if not data.get(id_key):
        raise SystemExit(f"{kind}: missing id field {id_key}")

    release = data.get("release") or {}
    if release.get("releaseId") != release_id:
        raise SystemExit(f"{kind}: releaseId={release.get('releaseId')} want {release_id}")

    if kind != "gitopsRealPRFileMaterialization":
        if not contains_pair(data, "branchName", branch):
            raise SystemExit(f"{kind}: missing branchName trace {branch}")
    else:
        if not contains_pair(data, "status", "FILES_MATERIALIZED"):
            raise SystemExit(f"{kind}: fileMaterialization.status must be FILES_MATERIALIZED")
        if not contains_pair(data, "gitopsRealPRMaterialization", None) and not any(k == "gitopsRealPRMaterialization" and isinstance(v, str) and v for k, v in walk(data)):
            raise SystemExit(f"{kind}: missing upstream gitopsRealPRMaterialization link")

    guardrails = data.get("guardrails") or {}
    if guardrails.get("doesNotModifyKubernetes") is not True:
        raise SystemExit(f"{kind}: guardrails.doesNotModifyKubernetes must be true")

commit_path = root / f"gitops-real-pr-local-commit-{release_id}.json"
commit = json.loads(commit_path.read_text(encoding="utf-8-sig"))
if not contains_pair(commit, "commitSha", None) and not any(k == "commitSha" and isinstance(v, str) and v for k, v in walk(commit)):
    raise SystemExit("gitopsRealPRLocalCommit: missing commitSha")

push_path = root / f"gitops-real-pr-push-preflight-{release_id}.json"
push = json.loads(push_path.read_text(encoding="utf-8-sig"))
if not contains_pair(push, "remoteBranchExists", False):
    raise SystemExit("gitopsRealPRPushPreflight: remoteBranchExists must be false in local acceptance")

print("PASS gitops real-pr local evidence completeness")
PY

echo "===== static controlled-write evidence emitters ====="
grep -q 'gitopsRealPRBranchPushId' scripts/run-gitops-real-pr-push-branch.sh
grep -q 'gitopsRealPRCreatePreflightId' scripts/build-gitops-real-pr-create-preflight.sh
grep -q 'gitopsRealPRCreateId' scripts/run-gitops-real-pr-create.sh
grep -q 'gitopsRealPRCleanupId' scripts/run-gitops-real-pr-cleanup.sh

echo "PASS gitops real-pr evidence completeness"
