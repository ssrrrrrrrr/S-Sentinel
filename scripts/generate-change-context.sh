#!/bin/bash
set -euo pipefail

BASE_REF="${BASE_REF:-HEAD^}"
OUTPUT_DIR="${OUTPUT_DIR:-docs/release-reports}"
APP_NAME="${APP_NAME:-demo-app}"
NAMESPACE="${NAMESPACE:-slo-rollout}"

ROLLOUT_FILE=""
ANALYSIS_FILE=""

if [ -f "deploy/base/rollout.yaml" ]; then
  ROLLOUT_FILE="deploy/base/rollout.yaml"
elif [ -f "deploy/rollout.yaml" ]; then
  ROLLOUT_FILE="deploy/rollout.yaml"
else
  echo "ERROR: rollout.yaml not found" >&2
  exit 1
fi

if [ -f "deploy/base/analysis.yaml" ]; then
  ANALYSIS_FILE="deploy/base/analysis.yaml"
elif [ -f "deploy/analysis.yaml" ]; then
  ANALYSIS_FILE="deploy/analysis.yaml"
else
  echo "ERROR: analysis.yaml not found" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

python3 - "$BASE_REF" "$OUTPUT_DIR" "$APP_NAME" "$NAMESPACE" "$ROLLOUT_FILE" "$ANALYSIS_FILE" <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

base_ref, output_dir, app_name, namespace, rollout_file, analysis_file = sys.argv[1:7]

def run(cmd, default=""):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return default

def read_current(path):
    p = Path(path)
    if not p.exists():
        return ""
    return p.read_text()

def read_from_git(ref, path):
    if not ref:
        return ""
    return run(["git", "show", f"{ref}:{path}"], default="")

def extract_image(text):
    m = re.search(r'^\s*image:\s*["\']?([^"\'\s]+)["\']?\s*$', text, re.M)
    return m.group(1) if m else ""

def extract_env(text):
    env = {}
    lines = text.splitlines()
    current_name = None

    for line in lines:
        name_match = re.match(r'^\s*-\s*name:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$', line)
        if name_match:
            current_name = name_match.group(1)
            continue

        value_match = re.match(r'^\s*value:\s*["\']?([^"\']*)["\']?\s*$', line)
        if value_match and current_name:
            env[current_name] = value_match.group(1)
            current_name = None

    return env

def extract_set_weights(text):
    return [int(x) for x in re.findall(r'setWeight:\s*([0-9]+)', text)]

def extract_metric_blocks(text):
    metrics = {}
    current = None

    for line in text.splitlines():
        name_match = re.match(r'^\s*-\s*name:\s*([A-Za-z0-9_.-]+)\s*$', line)
        if name_match:
            current = name_match.group(1)
            metrics[current] = {}
            continue

        if not current:
            continue

        for key in ["interval", "count", "failureLimit", "successCondition", "failureCondition"]:
            m = re.match(rf'^\s*{key}:\s*(.+?)\s*$', line)
            if m:
                metrics[current][key] = m.group(1).strip().strip('"').strip("'")

    return metrics

def diff_map(prev, curr):
    keys = sorted(set(prev.keys()) | set(curr.keys()))
    changes = []
    for key in keys:
        old = prev.get(key)
        new = curr.get(key)
        if old != new:
            changes.append({
                "name": key,
                "previous": old,
                "current": new,
                "changed": True,
            })
    return changes

def safe_float(value):
    try:
        return float(value)
    except Exception:
        return None

def classify_env_risk(name, old, new):
    if name == "FAULT_RATE":
        new_f = safe_float(new)
        old_f = safe_float(old)
        if new_f is not None and new_f >= 0.5:
            return "critical"
        if new_f is not None and old_f is not None and new_f > old_f:
            return "high"
    if name == "LATENCY_MS":
        new_f = safe_float(new)
        old_f = safe_float(old)
        if new_f is not None and new_f >= 500:
            return "high"
        if new_f is not None and old_f is not None and new_f > old_f:
            return "medium"
    if name in {"VERSION", "RELEASE_TAG"}:
        return "low"
    return "medium"

def build_risk(image_changed, env_changes, metric_changes, weights_changed):
    score = 0
    hints = []

    if image_changed:
        score += 20
        hints.append("image tag changed")

    for ch in env_changes:
        name = ch["name"]
        old = ch.get("previous")
        new = ch.get("current")
        risk = classify_env_risk(name, old, new)
        ch["risk"] = risk

        if name == "FAULT_RATE":
            new_f = safe_float(new)
            if new_f is not None and new_f > 0:
                score += 40 if new_f >= 0.5 else 25
                hints.append(f"FAULT_RATE is {new}")
        elif name == "LATENCY_MS":
            new_f = safe_float(new)
            if new_f is not None and new_f > 0:
                score += 30 if new_f >= 500 else 15
                hints.append(f"LATENCY_MS is {new}")
        elif name in {"VERSION", "RELEASE_TAG"}:
            score += 5

    if metric_changes:
        score += 15
        hints.append("SLO gate configuration changed")

    if weights_changed:
        score += 10
        hints.append("rollout canary steps changed")

    score = min(score, 100)

    if score >= 80:
        level = "critical"
    elif score >= 60:
        level = "high"
    elif score >= 30:
        level = "medium"
    else:
        level = "low"

    return level, score, hints

previous_rollout = read_from_git(base_ref, rollout_file)
previous_analysis = read_from_git(base_ref, analysis_file)

current_rollout = read_current(rollout_file)
current_analysis = read_current(analysis_file)

current_commit = run(["git", "rev-parse", "--short", "HEAD"], default="")
previous_commit = run(["git", "rev-parse", "--short", base_ref], default="")
commit_message = run(["git", "log", "-1", "--pretty=%s"], default="")

prev_image = extract_image(previous_rollout)
curr_image = extract_image(current_rollout)

prev_env = extract_env(previous_rollout)
curr_env = extract_env(current_rollout)

env_changes = diff_map(prev_env, curr_env)

prev_weights = extract_set_weights(previous_rollout)
curr_weights = extract_set_weights(current_rollout)

prev_metrics = extract_metric_blocks(previous_analysis)
curr_metrics = extract_metric_blocks(current_analysis)

metric_changes = []
for name in sorted(set(prev_metrics.keys()) | set(curr_metrics.keys())):
    if prev_metrics.get(name) != curr_metrics.get(name):
        metric_changes.append({
            "name": name,
            "previous": prev_metrics.get(name),
            "current": curr_metrics.get(name),
            "changed": True,
        })

risk_level, risk_score, risk_hints = build_risk(
    image_changed=(prev_image != curr_image),
    env_changes=env_changes,
    metric_changes=metric_changes,
    weights_changed=(prev_weights != curr_weights),
)

generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
ts = datetime.now().strftime("%Y%m%d-%H%M%S")

ctx = {
    "schemaVersion": "change-context/v1",
    "generatedAt": generated_at,
    "changeType": "gitops_release",
    "app": app_name,
    "namespace": namespace,
    "git": {
        "baseRef": base_ref,
        "previousCommit": previous_commit,
        "currentCommit": current_commit,
        "commitMessage": commit_message,
    },
    "files": {
        "rollout": rollout_file,
        "analysis": analysis_file,
    },
    "image": {
        "previous": prev_image,
        "current": curr_image,
        "changed": prev_image != curr_image,
    },
    "env": {
        "previous": prev_env,
        "current": curr_env,
        "changes": env_changes,
    },
    "rolloutStrategy": {
        "previousSetWeights": prev_weights,
        "currentSetWeights": curr_weights,
        "changed": prev_weights != curr_weights,
    },
    "sloGates": {
        "previous": prev_metrics,
        "current": curr_metrics,
        "changes": metric_changes,
    },
    "risk": {
        "level": risk_level,
        "score": risk_score,
        "hints": risk_hints,
    },
}

out_dir = Path(output_dir)
out_dir.mkdir(parents=True, exist_ok=True)

out_file = out_dir / f"change-context-{ts}.json"
latest_file = out_dir / "change-context-latest.json"

data = json.dumps(ctx, ensure_ascii=False, indent=2)
out_file.write_text(data + "\n")
latest_file.write_text(data + "\n")

print(f"Change context generated: {out_file}")
print(f"Latest change context: {latest_file}")
print(json.dumps({
    "imageChanged": ctx["image"]["changed"],
    "envChanges": len(env_changes),
    "sloGateChanges": len(metric_changes),
    "riskLevel": risk_level,
    "riskScore": risk_score,
    "riskHints": risk_hints,
}, ensure_ascii=False, indent=2))
PY
