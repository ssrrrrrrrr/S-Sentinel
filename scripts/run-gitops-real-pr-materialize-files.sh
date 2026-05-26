#!/usr/bin/env bash
set -euo pipefail

MATERIALIZATION_JSON="${1:-}"

if [ -z "$MATERIALIZATION_JSON" ] || [ ! -f "$MATERIALIZATION_JSON" ]; then
  echo "ERROR: materialization json not found: ${MATERIALIZATION_JSON:-empty}" >&2
  exit 1
fi

python3 - "$MATERIALIZATION_JSON" <<'PY'
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

mat_path = Path(sys.argv[1])
mat = json.loads(mat_path.read_text(encoding="utf-8-sig"))

release = mat.get("release") or {}
inputs = mat.get("inputs") or {}
m = mat.get("materialization") or {}

if m.get("materializationStatus") != "READY_TO_MATERIALIZE":
    raise SystemExit("ERROR: materialization is not READY_TO_MATERIALIZE")

repo_dir = Path(inputs["repoDir"])
commit_payload_path = Path(inputs["commitPayloadPath"])

if not repo_dir.exists():
    raise SystemExit(f"ERROR: repo dir does not exist: {repo_dir}")

payload = json.loads(commit_payload_path.read_text(encoding="utf-8-sig"))
patch_entries = payload.get("patchEntries") or []

written = []
blocked = []

def safe_target(repo: Path, target: str) -> Path:
    raw = Path(target)
    if raw.is_absolute() or ".." in raw.parts:
        raise ValueError(f"unsafe target path: {target}")
    return repo / raw

for entry in patch_entries:
    target = entry.get("targetRef") or entry.get("targetPath")
    if not target:
        blocked.append({"entryId": entry.get("entryId"), "reason": "missing targetRef/targetPath"})
        continue

    try:
        dst = safe_target(repo_dir, target)
    except ValueError as e:
        blocked.append({"entryId": entry.get("entryId"), "targetRef": target, "reason": str(e)})
        continue

    dst.parent.mkdir(parents=True, exist_ok=True)

    if entry.get("content") is not None:
        dst.write_text(str(entry["content"]), encoding="utf-8")
        written.append({"entryId": entry.get("entryId"), "targetRef": target, "mode": "inline_content"})
        continue

    if entry.get("renderedContent") is not None:
        dst.write_text(str(entry["renderedContent"]), encoding="utf-8")
        written.append({"entryId": entry.get("entryId"), "targetRef": target, "mode": "rendered_content"})
        continue

    source = entry.get("sourcePath") or entry.get("renderedFilePath") or entry.get("filePath")
    if source:
        src = Path(source)
        if not src.exists():
            blocked.append({"entryId": entry.get("entryId"), "targetRef": target, "reason": f"source not found: {source}"})
            continue
        shutil.copyfile(src, dst)
        written.append({"entryId": entry.get("entryId"), "targetRef": target, "mode": "source_file", "sourcePath": source})
        continue

    blocked.append({"entryId": entry.get("entryId"), "targetRef": target, "reason": "missing content/sourcePath/renderedFilePath"})

git_status = subprocess.check_output(
    ["git", "-C", str(repo_dir), "status", "--short"],
    text=True,
)

release_id = release.get("releaseId") or mat_path.stem.replace("gitops-real-pr-materialization-", "")

status = "FILES_MATERIALIZED" if written and not blocked else "PARTIALLY_MATERIALIZED" if written else "NO_FILES_MATERIALIZED"

out = {
    "schemaVersion": "gitops.real.pr.file.materialization/v1alpha1",
    "gitopsRealPRFileMaterializationId": "gprfiles-" + release_id,
    "generatedBy": "run-gitops-real-pr-materialize-files.sh",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "mode": "isolated_gitops_pr_file_materialization",
    "release": release,
    "inputs": {
        "gitopsRealPRMaterialization": str(mat_path),
        "repoDir": str(repo_dir),
        "commitPayloadPath": str(commit_payload_path)
    },
    "fileMaterialization": {
        "status": status,
        "writtenFileCount": len(written),
        "blockedFileCount": len(blocked),
        "writtenFiles": written,
        "blockedFiles": blocked,
        "gitStatusShort": git_status.splitlines()
    },
    "guardrails": {
        "readOnly": False,
        "dryRunOnly": False,
        "willExecute": False,
        "doesNotCommit": True,
        "doesNotPush": True,
        "doesNotCreatePullRequest": True,
        "doesNotModifyKubernetes": True
    }
}

output = mat_path.parent / f"gitops-real-pr-file-materialization-{release_id}.json"
latest = mat_path.parent / "gitops-real-pr-file-materialization-latest.json"

text = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
