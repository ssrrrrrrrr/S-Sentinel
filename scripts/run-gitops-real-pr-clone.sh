#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_FILE="${1:-}"

if [ -z "$WORKSPACE_FILE" ] || [ ! -f "$WORKSPACE_FILE" ]; then
  echo "ERROR: workspace file not found: ${WORKSPACE_FILE:-empty}" >&2
  exit 1
fi

python3 - "$WORKSPACE_FILE" <<'PY'
import json
import sys
from pathlib import Path

workspace_file = Path(sys.argv[1])
data = json.loads(workspace_file.read_text(encoding="utf-8-sig"))
ws = data.get("workspace") or {}

workspace_dir = Path(ws["workspaceDir"])
repo_dir = workspace_dir / "repo"
branch = ws.get("branchName") or ""

if ws.get("workspaceStatus") != "WORKSPACE_PREPARED":
    raise SystemExit("ERROR: workspace is not prepared")

if not branch:
    raise SystemExit("ERROR: branchName is missing")

print(str(workspace_dir))
print(str(repo_dir))
print(branch)
PY
