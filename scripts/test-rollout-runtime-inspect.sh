#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR=".tmp/test-rollout-runtime-inspect"
DB_PATH=".tmp/test-rollout-runtime-inspect.sqlite"

rm -rf "$TMP_DIR"
rm -f "$DB_PATH"
mkdir -p "$TMP_DIR"

echo "===== build rollout runtime inspect fixture ====="
S_SENTINEL_ROLLOUT_INSPECT_MODE="fixture" \
S_SENTINEL_RELEASE_ID="runtime-inspect-smoke" \
S_SENTINEL_SERVICE="demo-app" \
S_SENTINEL_ENV="dev" \
S_SENTINEL_NAMESPACE="slo-rollout" \
S_SENTINEL_ROLLOUT_NAME="demo-app" \
bash scripts/build-rollout-runtime-inspect.sh "$TMP_DIR"

cat "$TMP_DIR/rollout-runtime-inspect-runtime-inspect-smoke.json"

echo "===== assert raw contract ====="
python3 - <<'PY'
import json
from pathlib import Path

p = Path(".tmp/test-rollout-runtime-inspect/rollout-runtime-inspect-runtime-inspect-smoke.json")
data = json.loads(p.read_text())

assert data["schemaVersion"] == "runtime.rollout.inspect/v1alpha1", data
assert data["mode"] == "fixture_rollout_runtime_inspect", data
assert data["rolloutRuntimeInspectId"] == "rti-runtime-inspect-smoke", data
assert data["target"]["rolloutName"] == "demo-app", data
assert data["rollout"]["phase"] == "Progressing", data
assert data["rollout"]["strategy"] == "Canary", data
assert data["analysis"]["status"] == "Running", data
assert data["guardrails"]["readOnly"] is True, data
assert data["guardrails"]["dryRunOnly"] is True, data
assert data["guardrails"]["willExecute"] is False, data
assert data["guardrails"]["doesNotModifyKubernetes"] is True, data
PY

echo "===== import into EvidenceStore ====="
python3 scripts/evidence-store.py init-db --db "$DB_PATH" >/dev/null
python3 scripts/evidence-store.py import-dir --db "$DB_PATH" --report-dir "$TMP_DIR"

echo "===== search rolloutRuntimeInspect ====="
python3 scripts/evidence-store.py search-objects \
  --db "$DB_PATH" \
  --object-type rolloutRuntimeInspect \
  --release-id runtime-inspect-smoke \
  --limit 10 \
  >/tmp/ssentinel-rollout-runtime-inspect-search.json

cat /tmp/ssentinel-rollout-runtime-inspect-search.json

echo "===== assert EvidenceStore summary ====="
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/ssentinel-rollout-runtime-inspect-search.json").read_text())
items = data.get("items") or data.get("objects") or []
assert items, data

summary = items[0].get("summary") or {}
assert summary.get("objectType") == "rolloutRuntimeInspect", summary
assert summary.get("schemaVersion") == "runtime.rollout.inspect/v1alpha1", summary
assert summary.get("rolloutName") == "demo-app", summary
assert summary.get("namespace") == "slo-rollout", summary
assert summary.get("service") == "demo-app", summary
assert summary.get("env") == "dev", summary
assert summary.get("rolloutPhase") == "Progressing", summary
assert summary.get("strategy") == "Canary", summary
assert summary.get("analysisStatus") == "Running", summary
assert summary.get("readOnly") is True, summary
assert summary.get("dryRunOnly") is True, summary
assert summary.get("willExecute") is False, summary
assert summary.get("doesNotModifyKubernetes") is True, summary

print("PASS rollout runtime inspect")
PY
