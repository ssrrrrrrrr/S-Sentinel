#!/usr/bin/env bash
set -euo pipefail

SCHEMA_FILE="schemas/environment-config.schema.json"
CONFIG_DIR="configs/environments"

python3 - "$SCHEMA_FILE" "$CONFIG_DIR" <<'PY'
import json
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required: {exc}")

schema_path = Path(sys.argv[1])
config_dir = Path(sys.argv[2])

schema = json.loads(schema_path.read_text(encoding="utf-8"))
assert schema["title"] == "S Sentinel Environment Config"
assert schema["properties"]["apiVersion"]["const"] == "platform.ssentinel.io/v1alpha1"
assert schema["properties"]["kind"]["const"] == "EnvironmentConfig"

required_envs = ["dev", "staging", "prod"]
summary = []

for env_name in required_envs:
    env_path = config_dir / f"{env_name}.yaml"
    assert env_path.is_file(), env_path

    doc = yaml.safe_load(env_path.read_text(encoding="utf-8"))
    assert doc["apiVersion"] == "platform.ssentinel.io/v1alpha1"
    assert doc["kind"] == "EnvironmentConfig"
    assert doc["metadata"]["name"] == env_name
    assert doc["metadata"]["env"] == env_name

    spec = doc["spec"]
    assert spec["gitops"]["mode"] == "kustomize"
    assert Path(spec["gitops"]["basePath"]).is_dir()
    assert Path(spec["gitops"]["applicationPath"]).is_dir()

    assert spec["safety"]["readOnlyDefault"] is True
    assert spec["safety"]["willExecuteDefault"] is False
    assert spec["safety"]["requiresHumanApprovalForExecution"] is True

    for ref in spec["slo"]["configRefs"]:
        assert Path(ref).is_file(), ref

    for ref in spec["strategy"]["configRefs"]:
        assert Path(ref).is_file(), ref

    if env_name in ("staging", "prod"):
        assert spec["policies"]["approvalRequired"] is True
        assert spec["policies"]["executionMode"] == "manual_approval"
        assert spec["supplyChain"]["requireImageDigest"] is True
        assert spec["supplyChain"]["blockMutableTags"] is True

    if env_name == "dev":
        assert spec["policies"]["executionMode"] == "advisory_only"

    summary.append({
        "env": env_name,
        "cluster": spec["cluster"]["name"],
        "namespace": spec["kubernetes"]["namespace"],
        "policyProfile": spec["policies"]["policyProfile"],
        "executionMode": spec["policies"]["executionMode"],
        "overlayPath": spec["gitops"]["overlayPath"],
    })

print(json.dumps({"validatedEnvironments": summary}, ensure_ascii=False, indent=2))
print("PASS: environment config test passed")
PY
