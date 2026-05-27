#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR=".tmp/test-runtime-action-execution-result-mock-rollback"
DB_PATH=".tmp/test-evidence-store-runtime-action-execution-result-rollback.sqlite"
RELEASE_ID="runtime-action-rollback-execution-mock-smoke"

rm -f "$DB_PATH"

bash scripts/test-runtime-action-execution-result-mock-rollback.sh >/tmp/ssentinel-runtime-action-execution-result-rollback-store-source.log
tail -40 /tmp/ssentinel-runtime-action-execution-result-rollback-store-source.log

python3 scripts/evidence-store.py \
  import-dir \
  --db "$DB_PATH" \
  --report-dir "$REPORT_DIR" \
  >/tmp/ssentinel-runtime-action-execution-result-rollback-ingest.json

python3 scripts/evidence-store.py \
  search-objects \
  --db "$DB_PATH" \
  --object-type runtimeActionExecutionResult \
  --release-id "$RELEASE_ID" \
  --limit 5 \
  >/tmp/ssentinel-runtime-action-execution-result-rollback-search.json

cat /tmp/ssentinel-runtime-action-execution-result-rollback-search.json

python3 - <<'PY'
import json
from pathlib import Path

release_id = "runtime-action-rollback-execution-mock-smoke"
data = json.loads(Path("/tmp/ssentinel-runtime-action-execution-result-rollback-search.json").read_text(encoding="utf-8"))

items = data.get("items") or []
assert len(items) == 1, data
summary = items[0].get("summary") or {}
target = summary.get("rollbackTarget") or {}

assert summary.get("objectType") == "runtimeActionExecutionResult", summary
assert items[0].get("release_id") == release_id, items[0]
assert summary.get("runtimeActionExecutionResultId") == "raer-" + release_id, summary
assert summary.get("requestedAction") == "ROLLBACK_ROLLOUT", summary
assert summary.get("executionStatus") == "SUCCEEDED", summary
assert summary.get("verificationStatus") == "VERIFIED", summary
assert summary.get("commandMode") == "kubectl_argo_rollouts_undo_to_revision", summary
assert summary.get("rollbackVerified") is True, summary
assert summary.get("didRollback") is True, summary
assert summary.get("didPause") is False, summary
assert summary.get("didResume") is False, summary
assert summary.get("didPromote") is False, summary
assert summary.get("didAbort") is False, summary
assert summary.get("mutatedKubernetes") is True, summary
assert summary.get("mutatedGitOps") is False, summary
assert target.get("targetRevision") == 3, target
assert target.get("commandArgumentMode") == "explicit_to_revision", target

print("PASS evidence store runtime action execution result rollback")
PY
