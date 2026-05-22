#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="${ROOT_DIR}/schemas/progressive-delivery-strategy.schema.json"
CONFIG_DIR="${ROOT_DIR}/configs/services"

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

if [ ! -d "${CONFIG_DIR}" ]; then
  echo "FAIL: config directory not found: ${CONFIG_DIR}" >&2
  exit 1
fi

mapfile -t CONFIG_FILES < <(find "${CONFIG_DIR}" -type f \( -name "*.strategy.yaml" -o -name "*.strategy.yml" \) | sort)

if [ "${#CONFIG_FILES[@]}" -eq 0 ]; then
  echo "FAIL: no progressive delivery strategy files found under ${CONFIG_DIR}" >&2
  exit 1
fi

"$PYTHON_BIN" - "${SCHEMA_FILE}" "${CONFIG_FILES[@]}" <<'PY'
import json
import pathlib
import sys

schema_path = pathlib.Path(sys.argv[1])
config_paths = [pathlib.Path(p) for p in sys.argv[2:]]

try:
    import yaml
except Exception as exc:
    print("FAIL: Python package 'PyYAML' is required to parse strategy YAML files.", file=sys.stderr)
    print("Hint: install it with system package python3-yaml or pip package pyyaml.", file=sys.stderr)
    raise SystemExit(1) from exc

try:
    import jsonschema
except Exception as exc:
    print("FAIL: Python package 'jsonschema' is required to validate strategy schema.", file=sys.stderr)
    print("Hint: install it with system package python3-jsonschema or pip package jsonschema.", file=sys.stderr)
    raise SystemExit(1) from exc

with schema_path.open("r", encoding="utf-8") as f:
    schema = json.load(f)

validator_cls = jsonschema.validators.validator_for(schema)
validator_cls.check_schema(schema)
validator = validator_cls(schema)

failed = False

for path in config_paths:
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))

    if errors:
        failed = True
        print(f"FAIL: {path}")
        for error in errors:
            location = ".".join(str(p) for p in error.path) or "<root>"
            print(f"  - {location}: {error.message}")
    else:
        metadata = data.get("metadata", {})
        spec = data.get("spec", {})
        traffic = spec.get("traffic", {})
        steps = traffic.get("steps", [])
        step_summary = ", ".join(
            f"{step.get('name', '<missing>')}={step.get('setWeight', '<missing>')}%"
            for step in steps
        )
        print(
            "PASS: "
            f"{path} "
            f"service={metadata.get('service')} "
            f"env={metadata.get('env')} "
            f"strategyId={metadata.get('name')} "
            f"type={spec.get('strategyType')} "
            f"sloRef={spec.get('analysis', {}).get('sloRef')} "
            f"steps=[{step_summary}]"
        )

if failed:
    raise SystemExit(1)
PY
