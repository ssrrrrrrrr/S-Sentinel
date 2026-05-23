#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="${ROOT_DIR}/schemas/compiler-profile.schema.json"
PROFILE_DIR="${ROOT_DIR}/configs/compiler-profiles"
ENV_DIR="${ROOT_DIR}/configs/environments"

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

if [ ! -f "${SCHEMA_FILE}" ]; then
  echo "FAIL: schema file not found: ${SCHEMA_FILE}" >&2
  exit 1
fi

if [ ! -d "${PROFILE_DIR}" ]; then
  echo "FAIL: compiler profile directory not found: ${PROFILE_DIR}" >&2
  exit 1
fi

mapfile -t PROFILE_FILES < <(find "${PROFILE_DIR}" -type f \( -name "*.profile.yaml" -o -name "*.profile.yml" \) | sort)

if [ "${#PROFILE_FILES[@]}" -eq 0 ]; then
  echo "FAIL: no CompilerProfile files found under ${PROFILE_DIR}" >&2
  exit 1
fi

"$PYTHON_BIN" - "${ROOT_DIR}" "${SCHEMA_FILE}" "${ENV_DIR}" "${PROFILE_FILES[@]}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
schema_path = pathlib.Path(sys.argv[2])
env_dir = pathlib.Path(sys.argv[3])
profile_paths = [pathlib.Path(p) for p in sys.argv[4:]]

try:
    import yaml
except Exception as exc:
    print("FAIL: Python package 'PyYAML' is required to parse CompilerProfile YAML files.", file=sys.stderr)
    raise SystemExit(1) from exc

try:
    import jsonschema
except Exception as exc:
    print("FAIL: Python package 'jsonschema' is required to validate CompilerProfile schema.", file=sys.stderr)
    raise SystemExit(1) from exc

schema = json.loads(schema_path.read_text(encoding="utf-8"))
validator_cls = jsonschema.validators.validator_for(schema)
validator_cls.check_schema(schema)
validator = validator_cls(schema)

failed = False
profiles_by_name = {}
profiles_by_path = {}
profile_failed_paths = set()

def fail(path, message):
    global failed
    failed = True
    profile_failed_paths.add(str(path))
    print(f"FAIL: {path}")
    print(f"  - {message}")

def require(condition, path, message):
    if not condition:
        fail(path, message)

def non_empty_string(value):
    return isinstance(value, str) and bool(value.strip())

def load_yaml(path):
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)

for path in profile_paths:
    rel = path.relative_to(root) if path.is_relative_to(root) else path
    data = load_yaml(path)

    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
    if errors:
        failed = True
        print(f"FAIL: {rel}")
        for error in errors:
            location = ".".join(str(p) for p in error.path) or "<root>"
            print(f"  - {location}: {error.message}")
        continue

    metadata = data.get("metadata") or {}
    spec = data.get("spec") or {}
    name = metadata.get("name")
    service = metadata.get("service")

    require(data.get("apiVersion") == "compiler.ssentinel.io/v1alpha1", rel, "apiVersion must be compiler.ssentinel.io/v1alpha1")
    require(data.get("kind") == "CompilerProfile", rel, "kind must be CompilerProfile")
    require(non_empty_string(name), rel, "metadata.name must be non-empty")
    require(non_empty_string(service), rel, "metadata.service must be non-empty")

    service_config = spec.get("serviceConfig") or {}
    runtime_profile = spec.get("runtimeProfile") or {}
    metric_binding = spec.get("metricBinding") or {}
    renderer_refs = spec.get("rendererRefs") or {}
    guardrails = spec.get("guardrails") or {}

    require(non_empty_string(service_config.get("serviceName")), rel, "spec.serviceConfig.serviceName must be non-empty")
    require(non_empty_string(service_config.get("containerName")), rel, "spec.serviceConfig.containerName must be non-empty")
    require(non_empty_string(service_config.get("servicePortName")), rel, "spec.serviceConfig.servicePortName must be non-empty")
    require(isinstance(service_config.get("containerPort"), int) and service_config.get("containerPort") > 0, rel, "spec.serviceConfig.containerPort must be a positive integer")

    health = service_config.get("health") or {}
    require(non_empty_string(health.get("readinessPath")) and health.get("readinessPath").startswith("/"), rel, "spec.serviceConfig.health.readinessPath must start with /")
    require(non_empty_string(health.get("livenessPath")) and health.get("livenessPath").startswith("/"), rel, "spec.serviceConfig.health.livenessPath must start with /")

    require(runtime_profile.get("runtimeType") == "container", rel, "spec.runtimeProfile.runtimeType must be container")
    require(isinstance(runtime_profile.get("replicas"), int) and runtime_profile.get("replicas") >= 1, rel, "spec.runtimeProfile.replicas must be >= 1")
    require(isinstance(runtime_profile.get("revisionHistoryLimit"), int) and runtime_profile.get("revisionHistoryLimit") >= 0, rel, "spec.runtimeProfile.revisionHistoryLimit must be >= 0")
    require(runtime_profile.get("imagePullPolicy") in {"Always", "IfNotPresent", "Never"}, rel, "spec.runtimeProfile.imagePullPolicy must be Always/IfNotPresent/Never")

    require(metric_binding.get("provider") == "prometheus", rel, "spec.metricBinding.provider must be prometheus")
    require(metric_binding.get("bindingSource") == "CompilerProfile.spec.metricBinding.prometheus", rel, "spec.metricBinding.bindingSource must point to CompilerProfile.spec.metricBinding.prometheus")

    prom = metric_binding.get("prometheus") or {}
    require(non_empty_string(prom.get("requestCounter")), rel, "spec.metricBinding.prometheus.requestCounter must be non-empty")
    require(non_empty_string(prom.get("latencyHistogram")), rel, "spec.metricBinding.prometheus.latencyHistogram must be non-empty")
    require(non_empty_string(prom.get("errorStatusRegex")), rel, "spec.metricBinding.prometheus.errorStatusRegex must be non-empty")

    labels = prom.get("labels") or {}
    for key in ["namespace", "version", "status"]:
        require(non_empty_string(labels.get(key)), rel, f"spec.metricBinding.prometheus.labels.{key} must be non-empty")

    supported = set(metric_binding.get("supportedObjectiveTypes") or [])
    require({"request_count", "error_rate", "latency"}.issubset(supported), rel, "spec.metricBinding.supportedObjectiveTypes must include request_count/error_rate/latency")

    for key in ["rolloutTemplate", "analysisTemplateRenderer", "prometheusRuleRenderer", "environmentOverlayRenderer"]:
        require(non_empty_string(renderer_refs.get(key)), rel, f"spec.rendererRefs.{key} must be non-empty")

    require(guardrails.get("readOnly") is True, rel, "spec.guardrails.readOnly must be true")
    require(guardrails.get("willExecute") is False, rel, "spec.guardrails.willExecute must be false")
    require(guardrails.get("doesNotApplyKubernetes") is True, rel, "spec.guardrails.doesNotApplyKubernetes must be true")

    profiles_by_name[name] = data
    profiles_by_path[str(rel)] = data

    if str(rel) not in profile_failed_paths:
        print(
            "PASS: "
            f"{rel} "
            f"profile={name} "
            f"service={service} "
            f"runtime={runtime_profile.get('runtimeType')} "
            f"renderer={renderer_refs.get('rolloutTemplate')}"
        )

for env_name in ["dev", "staging", "prod"]:
    env_path = env_dir / f"{env_name}.yaml"
    if not env_path.is_file():
        fail(env_path, "EnvironmentConfig file is missing")
        continue

    env_doc = load_yaml(env_path)
    compiler = (env_doc.get("spec") or {}).get("compiler") or {}
    default_profile = compiler.get("defaultProfile")
    profile_refs = compiler.get("profileRefs") or []

    require(non_empty_string(default_profile), env_path.relative_to(root), "spec.compiler.defaultProfile must be non-empty")
    require(isinstance(profile_refs, list) and len(profile_refs) > 0, env_path.relative_to(root), "spec.compiler.profileRefs must be a non-empty list")

    resolved_names = []
    for ref in profile_refs:
        ref_path = root / ref
        if not ref_path.is_file():
            fail(env_path.relative_to(root), f"compiler profile ref does not exist: {ref}")
            continue

        ref_doc = load_yaml(ref_path)
        ref_name = (ref_doc.get("metadata") or {}).get("name")
        resolved_names.append(ref_name)

    require(default_profile in resolved_names, env_path.relative_to(root), f"defaultProfile {default_profile} must resolve from profileRefs")

    print(
        "PASS: "
        f"{env_path.relative_to(root)} "
        f"defaultCompilerProfile={default_profile} "
        f"profileRefs={profile_refs}"
    )

if failed:
    raise SystemExit(1)
PY
