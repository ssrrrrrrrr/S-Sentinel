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

TEST_OUT="${TEST_OUT:-/tmp/ssentinel-config-compiler-test}"
rm -rf "$TEST_OUT"
mkdir -p "$TEST_OUT"

for env in dev staging prod; do
  echo "===== compile ${env} ====="
  ./scripts/compile-release-config.sh \
    --env "$env" \
    --image-tag "v36-${env}" \
    --app-version "v36" \
    --fault-rate "0" \
    --latency-ms "0" \
    --output-dir "$TEST_OUT"

  echo "===== kustomize ${env} ====="
  kubectl kustomize "$TEST_OUT/$env" >/tmp/ssentinel-compiled-${env}.yaml
  grep -q "kind: Rollout" /tmp/ssentinel-compiled-${env}.yaml
  grep -q "kind: AnalysisTemplate" /tmp/ssentinel-compiled-${env}.yaml
  grep -q "kind: PrometheusRule" /tmp/ssentinel-compiled-${env}.yaml
done

"$PYTHON_BIN" - "$TEST_OUT" <<'PY'
import json
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])

expected_namespaces = {
    "dev": "slo-rollout",
    "staging": "slo-rollout-staging",
    "prod": "slo-rollout-prod",
}

expected_policy_profiles = {
    "dev": "dev-advisory",
    "staging": "staging-controlled",
    "prod": "prod-strict",
}

for env, namespace in expected_namespaces.items():
    env_dir = root / env
    analysis = yaml.safe_load((env_dir / "analysis.yaml").read_text(encoding="utf-8"))
    rollout = yaml.safe_load((env_dir / "rollout.yaml").read_text(encoding="utf-8"))
    prometheus_rule = yaml.safe_load((env_dir / "prometheusrule.yaml").read_text(encoding="utf-8"))
    plan = json.loads((env_dir / "rendered-release-plan.json").read_text(encoding="utf-8"))

    assert analysis["metadata"]["namespace"] == namespace, analysis["metadata"]
    assert rollout["metadata"]["namespace"] == namespace, rollout["metadata"]
    assert plan["release"]["namespace"] == namespace, plan["release"]
    assert plan["release"]["service"] == "demo-app", plan["release"]
    assert plan["release"]["serviceSource"] == "sloConfig", plan["release"]
    assert plan["release"]["policyProfile"] == expected_policy_profiles[env], plan["release"]
    assert plan["release"]["project"] == "slo-rollout-demo", plan["release"]
    assert plan["release"]["imageRepository"] == "sre/demo-app", plan["release"]

    metrics = {item["name"]: item for item in analysis["spec"]["metrics"]}
    assert set(metrics) == {"request-count", "error-rate", "p95-latency"}, metrics

    assert metrics["request-count"]["successCondition"] == "result[0] >= 20", metrics["request-count"]
    assert metrics["error-rate"]["successCondition"] == "result[0] <= 5", metrics["error-rate"]
    assert metrics["p95-latency"]["successCondition"] == "isNaN(result[0]) || result[0] <= 0.5", metrics["p95-latency"]

    rollout_steps = rollout["spec"]["strategy"]["canary"]["steps"]
    weights = [item["setWeight"] for item in rollout_steps if "setWeight" in item]
    pauses = [item["pause"]["duration"] for item in rollout_steps if "pause" in item]

    assert weights == [20, 50, 100], weights
    assert pauses == ["30s", "60s"], pauses

    rendered = yaml.safe_dump(prometheus_rule, sort_keys=False)
    assert "> 5" in rendered, rendered
    assert "> 0.5" in rendered, rendered
    assert ">= 20" in rendered, rendered

    assert plan["inputs"]["sloConfigRef"] == "configs/services/demo-app.slo.yaml", plan["inputs"]
    assert plan["inputs"]["strategyConfigRef"] == "configs/services/demo-app.strategy.yaml", plan["inputs"]

    source_refs = plan["sourceConfigRefs"]
    assert source_refs["environmentConfig"]["path"] == f"configs/environments/{env}.yaml", source_refs
    assert source_refs["sloConfig"]["name"] == "demo-app-canary-slo", source_refs
    assert source_refs["progressiveDeliveryStrategy"]["name"] == "demo-app-canary-strategy", source_refs

    inventory = plan["hardcodeInventory"]
    assert inventory["status"] == "known_demo_bindings_present", inventory
    binding_ids = {item["id"] for item in inventory["remainingBindings"]}
    prom = plan["slo"]["observability"]["prometheus"]
    assert prom["requestCounter"] == "demo_http_requests_total", prom
    assert prom["latencyHistogram"] == "demo_http_request_duration_seconds_bucket", prom
    assert prom["errorStatusRegex"] == "5..", prom

    assert binding_ids == {"demo-runtime-fault-env"}, binding_ids

    assert "prometheus-request-counter-demo" not in binding_ids, binding_ids
    assert "prometheus-latency-histogram-demo" not in binding_ids, binding_ids
    assert "default-service-demo-app" not in binding_ids, binding_ids
    assert "default-image-name-sre-demo-app" not in binding_ids, binding_ids
    assert "prometheus-alert-name-demoapp" not in binding_ids, binding_ids
    assert "prometheus-project-label-demo" not in binding_ids, binding_ids
    assert inventory["guardrails"]["inventoryOnly"] is True, inventory["guardrails"]

    assert plan["guardrails"]["doesNotApplyKubernetes"] is True, plan["guardrails"]
    assert plan["guardrails"]["doesNotCommitOrPush"] is True, plan["guardrails"]
    assert plan["guardrails"]["doesNotBuildImages"] is True, plan["guardrails"]

print("PASS: config compiler test passed")
PY
