#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python runtime not found. Set PYTHON_BIN=/path/to/python." >&2
    exit 1
  fi
fi

export PYTHON_BIN

TEST_OUT="${TEST_OUT:-/tmp/ssentinel-stage46-compiler-profile-model}"
rm -rf "$TEST_OUT"
mkdir -p "$TEST_OUT"

echo "===== compile dev with compiler profile ====="
./scripts/compile-release-config.sh \
  --env dev \
  --image-tag "v46-profile" \
  --app-version "v46" \
  --fault-rate "0" \
  --latency-ms "0" \
  --output-dir "$TEST_OUT"

echo "===== kustomize compiled dev ====="
kubectl kustomize "$TEST_OUT/dev" >/tmp/ssentinel-stage46-compiler-profile-model.yaml
grep -q "kind: Rollout" /tmp/ssentinel-stage46-compiler-profile-model.yaml
grep -q "kind: AnalysisTemplate" /tmp/ssentinel-stage46-compiler-profile-model.yaml
grep -q "kind: PrometheusRule" /tmp/ssentinel-stage46-compiler-profile-model.yaml

echo "===== assert compiler profile model ====="
"$PYTHON_BIN" - "$TEST_OUT" <<'PY'
import json
import sys
from pathlib import Path

import yaml

out = Path(sys.argv[1])
profile_path = Path("configs/compiler-profiles/demo-app.profile.yaml")
schema_path = Path("schemas/compiler-profile.schema.json")

profile = yaml.safe_load(profile_path.read_text(encoding="utf-8"))
schema = json.loads(schema_path.read_text(encoding="utf-8"))
env = yaml.safe_load(Path("configs/environments/dev.yaml").read_text(encoding="utf-8"))

assert schema["properties"]["kind"]["const"] == "CompilerProfile", schema
assert profile["apiVersion"] == "compiler.ssentinel.io/v1alpha1", profile
assert profile["kind"] == "CompilerProfile", profile
assert profile["metadata"]["name"] == "demo-app-compiler-profile", profile
assert profile["metadata"]["service"] == "demo-app", profile

spec = profile["spec"]
for key in ["serviceConfig", "runtimeProfile", "metricBinding", "rendererRefs", "guardrails"]:
    assert key in spec, profile

assert spec["serviceConfig"]["containerPort"] == 8080, spec["serviceConfig"]
assert spec["runtimeProfile"]["replicas"] == 3, spec["runtimeProfile"]
assert spec["metricBinding"]["provider"] == "prometheus", spec["metricBinding"]
assert spec["rendererRefs"]["rolloutTemplate"] == "argo-rollouts-canary-v1", spec["rendererRefs"]
assert spec["rendererRefs"]["analysisTemplateRenderer"] == "prometheus-analysis-template-v1", spec["rendererRefs"]
assert spec["rendererRefs"]["environmentOverlayRenderer"] == "kustomize-overlay-v1", spec["rendererRefs"]
assert spec["guardrails"]["profileModelOnly"] is True, spec["guardrails"]

assert env["spec"]["compiler"]["defaultProfile"] == "demo-app-compiler-profile", env["spec"]["compiler"]
assert "configs/compiler-profiles/demo-app.profile.yaml" in env["spec"]["compiler"]["profileRefs"], env["spec"]["compiler"]

env_dir = out / "dev"
plan = json.loads((env_dir / "rendered-release-plan.json").read_text(encoding="utf-8"))
analysis = yaml.safe_load((env_dir / "analysis.yaml").read_text(encoding="utf-8"))
rollout = yaml.safe_load((env_dir / "rollout.yaml").read_text(encoding="utf-8"))
prometheus_rule = yaml.safe_load((env_dir / "prometheusrule.yaml").read_text(encoding="utf-8"))

compiler_profile = plan["compilerProfile"]
assert compiler_profile["enabled"] is True, compiler_profile
assert compiler_profile["profileId"] == "demo-app-compiler-profile", compiler_profile
assert compiler_profile["profileRef"] == "configs/compiler-profiles/demo-app.profile.yaml", compiler_profile
assert compiler_profile["serviceConfig"]["serviceName"] == "demo-app", compiler_profile
assert compiler_profile["runtimeProfile"]["runtimeType"] == "container", compiler_profile
assert compiler_profile["metricBinding"]["provider"] == "prometheus", compiler_profile
assert compiler_profile["rendererRefs"]["prometheusRuleRenderer"] == "prometheus-rule-v1", compiler_profile
assert compiler_profile["guardrails"]["profileModelOnly"] is True, compiler_profile
assert compiler_profile["guardrails"]["doesNotChangeRenderedManifests"] is True, compiler_profile
assert compiler_profile["guardrails"]["doesNotApplyKubernetes"] is True, compiler_profile

assert plan["inputs"]["compilerProfileRef"] == "configs/compiler-profiles/demo-app.profile.yaml", plan["inputs"]
assert plan["sourceConfigRefs"]["compilerProfile"]["name"] == "demo-app-compiler-profile", plan["sourceConfigRefs"]

# 46.1 is model-only: rendered resource kinds and core names remain the same.
assert analysis["kind"] == "AnalysisTemplate", analysis
assert rollout["kind"] == "Rollout", rollout
assert prometheus_rule["kind"] == "PrometheusRule", prometheus_rule
assert analysis["metadata"]["name"] == "demo-app-error-rate", analysis["metadata"]
assert rollout["metadata"]["name"] == "demo-app", rollout["metadata"]
assert prometheus_rule["metadata"]["name"] == "demo-app-rollout-alerts", prometheus_rule["metadata"]

print("PASS: Stage46 CompilerProfile model is valid")
PY

echo "PASS: Stage46 compiler profile model test passed"
