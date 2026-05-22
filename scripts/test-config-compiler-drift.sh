#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_ROOT="${WORK_ROOT:-/tmp/ssentinel-config-compiler-drift}"
REPO_COPY="$WORK_ROOT/repo"
OUT_DIR="$WORK_ROOT/out"

rm -rf "$WORK_ROOT"
mkdir -p "$REPO_COPY/scripts" "$OUT_DIR"

echo "===== prepare isolated config compiler workspace ====="
cp -a "$ROOT_DIR/configs" "$REPO_COPY/"
cp "$ROOT_DIR/scripts/compile-release-config.sh" "$REPO_COPY/scripts/compile-release-config.sh"
chmod +x "$REPO_COPY/scripts/compile-release-config.sh"

cd "$REPO_COPY"

echo "===== baseline compile ====="
./scripts/compile-release-config.sh \
  --env dev \
  --image-tag v36-baseline \
  --app-version v36 \
  --fault-rate 0 \
  --latency-ms 0 \
  --output-dir "$OUT_DIR/baseline"

echo "===== mutate SLOConfig thresholds ====="
python3 - <<'PY'
from pathlib import Path
import yaml

p = Path("configs/services/demo-app.slo.yaml")
data = yaml.safe_load(p.read_text(encoding="utf-8"))

for obj in data["spec"]["objectives"]:
    if obj["id"] == "error-rate":
        obj["threshold"]["value"] = 3
    if obj["id"] == "p95-latency":
        obj["threshold"]["value"] = 0.8

p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")
PY

./scripts/compile-release-config.sh \
  --env dev \
  --image-tag v36-slo-mutated \
  --app-version v36 \
  --fault-rate 0 \
  --latency-ms 0 \
  --output-dir "$OUT_DIR/slo-mutated"

echo "===== mutate ProgressiveDeliveryStrategy steps ====="
python3 - <<'PY'
from pathlib import Path
import yaml

p = Path("configs/services/demo-app.strategy.yaml")
data = yaml.safe_load(p.read_text(encoding="utf-8"))

data["spec"]["traffic"]["steps"] = [
    {"name": "small-canary", "setWeight": 10, "pause": "15s"},
    {"name": "medium-canary", "setWeight": 40, "pause": "45s"},
    {"name": "large-canary", "setWeight": 80, "pause": "90s"},
    {"name": "full-promotion", "setWeight": 100, "pause": "0s"},
]

p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")
PY

./scripts/compile-release-config.sh \
  --env dev \
  --image-tag v36-strategy-mutated \
  --app-version v36 \
  --fault-rate 0 \
  --latency-ms 0 \
  --output-dir "$OUT_DIR/strategy-mutated"

echo "===== verify drift behavior ====="
python3 - "$OUT_DIR" <<'PY'
import sys
from pathlib import Path
import yaml

out = Path(sys.argv[1])

def load_yaml(path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))

baseline_analysis = load_yaml(out / "baseline/dev/analysis.yaml")
slo_analysis = load_yaml(out / "slo-mutated/dev/analysis.yaml")
baseline_rule = load_yaml(out / "baseline/dev/prometheusrule.yaml")
slo_rule = load_yaml(out / "slo-mutated/dev/prometheusrule.yaml")
baseline_rollout = load_yaml(out / "baseline/dev/rollout.yaml")
strategy_rollout = load_yaml(out / "strategy-mutated/dev/rollout.yaml")

def metrics(doc):
    return {item["name"]: item for item in doc["spec"]["metrics"]}

base_metrics = metrics(baseline_analysis)
slo_metrics = metrics(slo_analysis)

assert base_metrics["error-rate"]["successCondition"] == "result[0] <= 5"
assert base_metrics["p95-latency"]["successCondition"] == "isNaN(result[0]) || result[0] <= 0.5"

assert slo_metrics["error-rate"]["successCondition"] == "result[0] <= 3"
assert slo_metrics["p95-latency"]["successCondition"] == "isNaN(result[0]) || result[0] <= 0.8"

baseline_rule_text = yaml.safe_dump(baseline_rule, sort_keys=False)
slo_rule_text = yaml.safe_dump(slo_rule, sort_keys=False)

assert "> 5" in baseline_rule_text
assert "> 0.5" in baseline_rule_text
assert "> 3" in slo_rule_text
assert "> 0.8" in slo_rule_text

def rollout_weights(doc):
    return [item["setWeight"] for item in doc["spec"]["strategy"]["canary"]["steps"] if "setWeight" in item]

def rollout_pauses(doc):
    return [item["pause"]["duration"] for item in doc["spec"]["strategy"]["canary"]["steps"] if "pause" in item]

assert rollout_weights(baseline_rollout) == [20, 50, 100]
assert rollout_pauses(baseline_rollout) == ["30s", "60s"]

assert rollout_weights(strategy_rollout) == [10, 40, 80, 100]
assert rollout_pauses(strategy_rollout) == ["15s", "45s", "90s"]

print("PASS: SLO threshold drift changes AnalysisTemplate and PrometheusRule")
print("PASS: strategy step drift changes Rollout canary steps")
print("PASS: config compiler is configuration-driven")
PY
