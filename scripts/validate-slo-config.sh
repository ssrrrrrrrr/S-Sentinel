#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="${ROOT_DIR}/schemas/slo-config.schema.json"
CONFIG_DIR="${ROOT_DIR}/configs/services"

if [ ! -f "${SCHEMA_FILE}" ]; then
  echo "FAIL: schema file not found: ${SCHEMA_FILE}" >&2
  exit 1
fi

if [ ! -d "${CONFIG_DIR}" ]; then
  echo "FAIL: config directory not found: ${CONFIG_DIR}" >&2
  exit 1
fi

mapfile -t CONFIG_FILES < <(find "${CONFIG_DIR}" -type f \( -name "*.slo.yaml" -o -name "*.slo.yml" \) | sort)

if [ "${#CONFIG_FILES[@]}" -eq 0 ]; then
  echo "FAIL: no SLO config files found under ${CONFIG_DIR}" >&2
  exit 1
fi

python3 - "${SCHEMA_FILE}" "${CONFIG_FILES[@]}" <<'PY'
import json
import pathlib
import sys

schema_path = pathlib.Path(sys.argv[1])
config_paths = [pathlib.Path(p) for p in sys.argv[2:]]

try:
    import yaml
except Exception as exc:
    print("FAIL: Python package 'PyYAML' is required to parse SLO YAML files.", file=sys.stderr)
    print("Hint: install it with: python3 -m pip install --user pyyaml", file=sys.stderr)
    raise SystemExit(1) from exc

try:
    import jsonschema
except Exception as exc:
    print("FAIL: Python package 'jsonschema' is required to validate SLO config schema.", file=sys.stderr)
    print("Hint: install it with: python3 -m pip install --user jsonschema", file=sys.stderr)
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
        objectives = data.get("spec", {}).get("objectives", [])
        objective_ids = ", ".join(obj.get("id", "<missing>") for obj in objectives)
        print(
            "PASS: "
            f"{path} "
            f"service={metadata.get('service')} "
            f"env={metadata.get('env')} "
            f"sloId={metadata.get('name')} "
            f"objectives=[{objective_ids}]"
        )

if failed:
    raise SystemExit(1)
PY
