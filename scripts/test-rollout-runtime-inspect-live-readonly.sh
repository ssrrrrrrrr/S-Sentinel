#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-rollout-runtime-inspect-live-readonly"
DB_PATH=".tmp/test-rollout-runtime-inspect-live-readonly.sqlite"

NAMESPACE="${S_SENTINEL_NAMESPACE:-slo-rollout}"
ROLLOUT_NAME="${S_SENTINEL_ROLLOUT_NAME:-demo-app}"
SERVICE="${S_SENTINEL_SERVICE:-demo-app}"

rm -rf "$TMP_DIR"
rm -f "$DB_PATH"
mkdir -p "$TMP_DIR"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "SKIP: kubectl not found"
  exit 0
fi

if ! kubectl -n "$NAMESPACE" get rollout "$ROLLOUT_NAME" >/dev/null 2>&1; then
  echo "SKIP: rollout $NAMESPACE/$ROLLOUT_NAME not found"
  exit 0
fi

echo "===== build live-readonly rollout runtime inspect ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="live-readonly" \
S_SENTINEL_RELEASE_ID="runtime-inspect-live-readonly-smoke" \
S_SENTINEL_SERVICE="$SERVICE" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="$NAMESPACE" \
S_SENTINEL_ROLLOUT_NAME="$ROLLOUT_NAME" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

cat "$TMP_DIR/rollout-runtime-inspect-runtime-inspect-live-readonly-smoke.json"

echo "===== assert live-readonly raw contract ====="
python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-rollout-runtime-inspect-live-readonly/rollout-runtime-inspect-runtime-inspect-live-readonly-smoke.json")
data = json.loads(p.read_text())

assert data["schemaVersion"] == "runtime.rollout.inspect/v1alpha1", data
assert data["mode"] == "live_readonly_rollout_runtime_inspect", data
assert data["target"]["rolloutName"], data
assert data["rollout"]["phase"], data
assert data["rollout"]["strategy"] in ("Canary", "BlueGreen", "Unknown"), data
assert data["guardrails"]["readOnly"] is True, data
assert data["guardrails"]["dryRunOnly"] is True, data
assert data["guardrails"]["willExecute"] is False, data
assert data["guardrails"]["doesNotModifyKubernetes"] is True, data
assert data["guardrails"]["doesNotPause"] is True, data
assert data["guardrails"]["doesNotPromote"] is True, data
assert data["guardrails"]["doesNotAbort"] is True, data
assert data["guardrails"]["doesNotRollback"] is True, data
PY

echo "===== import into EvidenceStore ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$TMP_DIR"

echo "===== search rolloutRuntimeInspect ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type rolloutRuntimeInspect \
  --release-id runtime-inspect-live-readonly-smoke \
  --limit 10 \
  >/tmp/ssentinel-rollout-runtime-inspect-live-readonly-search.json

cat /tmp/ssentinel-rollout-runtime-inspect-live-readonly-search.json

echo "===== assert EvidenceStore summary ====="
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/ssentinel-rollout-runtime-inspect-live-readonly-search.json").read_text())
items = data.get("items") or data.get("objects") or []
assert items, data

summary = items[0].get("summary") or {}
assert summary.get("objectType") == "rolloutRuntimeInspect", summary
assert summary.get("schemaVersion") == "runtime.rollout.inspect/v1alpha1", summary
assert summary.get("rolloutName"), summary
assert summary.get("namespace"), summary
assert summary.get("rolloutPhase"), summary
assert summary.get("strategy") in ("Canary", "BlueGreen", "Unknown"), summary
assert summary.get("readOnly") is True, summary
assert summary.get("dryRunOnly") is True, summary
assert summary.get("willExecute") is False, summary
assert summary.get("doesNotModifyKubernetes") is True, summary

print("PASS rollout runtime inspect live-readonly")
PY
