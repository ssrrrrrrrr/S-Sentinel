#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DB_PATH=".tmp/test-evidence-store-gitops-real-pr-local-flow.sqlite"
rm -f "$DB_PATH"

echo "===== generate local real-pr flow evidence ====="
bash scripts/test-gitops-real-pr-local-flow.sh >/tmp/ssentinel-real-pr-local-flow-evidence.log 2>&1
cat /tmp/ssentinel-real-pr-local-flow-evidence.log

LATEST_DIR="$(ls -td .tmp/test-gitops-real-pr-local-flow-* 2>/dev/null | head -1)"
if [ -z "$LATEST_DIR" ] || [ ! -d "$LATEST_DIR" ]; then
  echo "ERROR: local-flow evidence dir not found" >&2
  exit 1
fi

echo "latestEvidenceDir=$LATEST_DIR"

echo "===== import local-flow evidence into EvidenceStore ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$LATEST_DIR"

RELEASE_ID="$(basename "$LATEST_DIR" | sed 's/^test-gitops-real-pr-local-flow-/local-flow-/')"
echo "releaseId=$RELEASE_ID"

for object_type in \
  gitopsRealPRFileMaterialization \
  gitopsRealPRLocalCommit \
  gitopsRealPRPushPreflight
do
  echo "===== search $object_type ====="
  python3 scripts/evidence-store.py search-objects \
    --db "$DB_PATH" \
    --object-type "$object_type" \
    --release-id "$RELEASE_ID" \
    --limit 10 \
    > "/tmp/ssentinel-${object_type}.json"
  cat "/tmp/ssentinel-${object_type}.json"
done

echo "===== assert local-flow evidence summaries ====="
python3 - <<'PY'
import json
from pathlib import Path

def first_summary(object_type: str) -> dict:
    data = json.loads(Path(f"/tmp/ssentinel-{object_type}.json").read_text())
    items = data.get("items") or data.get("objects") or []
    assert items, data
    return items[0].get("summary") or {}

files = first_summary("gitopsRealPRFileMaterialization")
commit = first_summary("gitopsRealPRLocalCommit")
push_pf = first_summary("gitopsRealPRPushPreflight")

assert files.get("fileMaterializationStatus") == "FILES_MATERIALIZED", files
assert files.get("willExecute") is True, files
assert files.get("didMaterializeFiles") is True, files
assert files.get("doesNotCommit") is True, files
assert files.get("doesNotPush") is True, files
assert files.get("doesNotCreatePullRequest") is True, files
assert files.get("doesNotModifyKubernetes") is True, files

assert commit.get("commitStatus") == "LOCAL_COMMIT_CREATED", commit
assert commit.get("branchName", "").startswith("ssentinel/local-flow-"), commit
assert commit.get("willExecute") is True, commit
assert commit.get("didCreateLocalCommit") is True, commit
assert commit.get("doesNotPush") is True, commit
assert commit.get("doesNotCreatePullRequest") is True, commit
assert commit.get("doesNotModifyKubernetes") is True, commit

assert push_pf.get("preflightStatus") == "READY_TO_PUSH_BRANCH", push_pf
assert push_pf.get("branchName", "").startswith("ssentinel/local-flow-"), push_pf
assert push_pf.get("remoteBranchExists") is False, push_pf
assert push_pf.get("willExecute") is False, push_pf
assert push_pf.get("readOnly") is True, push_pf
assert push_pf.get("dryRunOnly") is True, push_pf
assert push_pf.get("doesNotPush") is True, push_pf
assert push_pf.get("doesNotCreatePullRequest") is True, push_pf
assert push_pf.get("doesNotModifyKubernetes") is True, push_pf

print("PASS evidence-store gitops real-pr local-flow summaries")
PY
