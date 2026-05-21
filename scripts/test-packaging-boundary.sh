#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import sys

try:
    import yaml
except Exception as exc:
    raise SystemExit(f"PyYAML is required: {exc}")

def load_yaml(path: Path):
    if not path.is_file():
        raise AssertionError(f"missing file: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise AssertionError(f"{path} must be a YAML object")
    return data

def require_kustomization(path: Path):
    data = load_yaml(path)
    assert data.get("apiVersion") == "kustomize.config.k8s.io/v1beta1", data
    assert data.get("kind") == "Kustomization", data
    resources = data.get("resources")
    assert isinstance(resources, list) and resources, data
    return data

root = require_kustomization(Path("deploy/kustomization.yaml"))
base = require_kustomization(Path("deploy/base/kustomization.yaml"))

# Safety: current root deployment entry remains dev only.
assert root["resources"] == ["overlays/dev"], root

base_required = {
    "rollout.yaml",
    "service.yaml",
    "analysis.yaml",
    "prometheusrule.yaml",
    "servicemonitor.yaml",
    "watcher-deployment.yaml",
    "watcher-rbac.yaml",
}

base_resources = set(base["resources"])
missing_base = sorted(base_required - base_resources)
assert not missing_base, f"base kustomization missing resources: {missing_base}"

summary = []

for env in ["dev", "staging", "prod"]:
    overlay_path = Path("deploy/overlays") / env
    kustomization_path = overlay_path / "kustomization.yaml"
    overlay = require_kustomization(kustomization_path)

    assert overlay["resources"] == ["../../base"], overlay

    env_config_path = Path("configs/environments") / f"{env}.yaml"
    env_config = load_yaml(env_config_path)
    configured_overlay = env_config["spec"]["gitops"]["overlayPath"]

    assert configured_overlay == str(overlay_path), (
        f"{env_config_path}: overlayPath={configured_overlay}, expected={overlay_path}"
    )

    summary.append({
        "env": env,
        "overlayPath": str(overlay_path),
        "baseRef": overlay["resources"][0],
    })

print({
    "rootApplication": root["resources"],
    "validatedOverlays": summary,
})
print("PASS: packaging boundary test passed")
PY
