#!/usr/bin/env bash
set -euo pipefail

TEST_TMP="${1:-/tmp/slo-environment-selection-test}"
REPORT_DIR="docs/release-reports"

rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

latest_file() {
  local pattern="$1"
  python3 - "$pattern" <<'PY'
import glob
import os
import sys

files = [f for f in glob.glob(sys.argv[1]) if os.path.isfile(f)]
files.sort(key=lambda f: os.path.getmtime(f), reverse=True)
if files:
    print(files[0])
PY
}

ai_decision="$(latest_file "$REPORT_DIR/ai-decision-*.json")"

if [ -z "$ai_decision" ] || [ ! -f "$ai_decision" ]; then
  echo "ERROR: no ai decision found under $REPORT_DIR" >&2
  exit 1
fi

ai_base="$(basename "$ai_decision")"
ai_suffix="${ai_base#ai-decision-}"
policy_decision="$REPORT_DIR/policy-decision-$ai_suffix"

if [ ! -f "$policy_decision" ]; then
  echo "ERROR: matching policy decision not found: $policy_decision" >&2
  exit 1
fi

run_case() {
  local name="$1"
  local expected_env="$2"
  local mode="$3"
  local expected_cluster="$4"
  local expected_policy="$5"
  local expected_overlay="$6"

  local case_dir="$TEST_TMP/$name"
  mkdir -p "$case_dir"

  if [ "$mode" = "env" ]; then
    (
      unset S_SENTINEL_ENV_CONFIG
      export S_SENTINEL_ENV="$expected_env"
      export RELEASE_REPORT_DIR="$case_dir"
      ./scripts/build-release-evidence.sh "$ai_decision" "$policy_decision" >"$case_dir/build-release-evidence.log" 2>&1
    )
  elif [ "$mode" = "config" ]; then
    (
      unset S_SENTINEL_ENV
      export S_SENTINEL_ENV_CONFIG="configs/environments/${expected_env}.yaml"
      export RELEASE_REPORT_DIR="$case_dir"
      ./scripts/build-release-evidence.sh "$ai_decision" "$policy_decision" >"$case_dir/build-release-evidence.log" 2>&1
    )
  else
    echo "ERROR: unknown mode: $mode" >&2
    exit 1
  fi

  cat "$case_dir/build-release-evidence.log"

  local release_evidence
  release_evidence="$(latest_file "$case_dir/release-evidence-*.json")"

  [ -f "$release_evidence" ] || {
    echo "ERROR: release evidence not generated for $name" >&2
    exit 1
  }

  EVIDENCE_RECORD_OUTPUT_DIR="$case_dir" ./scripts/build-evidence-record.sh "$release_evidence" >"$case_dir/build-evidence-record.log" 2>&1
  cat "$case_dir/build-evidence-record.log"

  local evidence_record="$case_dir/evidence-record-$(basename "$release_evidence" | sed 's/^release-evidence-//')"

  python3 - "$release_evidence" "$evidence_record" "$expected_env" "$expected_cluster" "$expected_policy" "$expected_overlay" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
record_path = Path(sys.argv[2])
expected_env = sys.argv[3]
expected_cluster = sys.argv[4]
expected_policy = sys.argv[5]
expected_overlay = sys.argv[6]

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
record = json.loads(record_path.read_text(encoding="utf-8"))

expected_config = f"configs/environments/{expected_env}.yaml"

assert evidence["env"] == expected_env, evidence
assert evidence["environmentConfigRef"] == expected_config, evidence
assert evidence["environment"]["profile"] == expected_env, evidence["environment"]
assert evidence["environment"]["clusterName"] == expected_cluster, evidence["environment"]
assert evidence["environment"]["policyProfile"] == expected_policy, evidence["environment"]
assert evidence["environment"]["gitopsOverlayPath"] == expected_overlay, evidence["environment"]
assert evidence["environment"]["configFound"] is True, evidence["environment"]

assert record["env"] == expected_env, record
assert record["environmentConfigRef"] == expected_config, record
assert record["environmentProfile"] == expected_env, record
assert record["clusterName"] == expected_cluster, record
assert record["policyProfile"] == expected_policy, record
assert record["gitopsOverlayPath"] == expected_overlay, record
assert record["environment"]["configCaptured"] is True, record["environment"]
assert record["links"]["environmentConfig"] == expected_config, record["links"]
assert record["artifacts"]["environmentConfig"]["exists"] is True, record["artifacts"]["environmentConfig"]

print(f"PASS: environment selection case passed: {expected_env}")
PY
}

run_case "staging-env-override" "staging" "env" "staging-cluster" "staging-controlled" "deploy/overlays/staging"
run_case "prod-config-override" "prod" "config" "prod-cluster" "prod-strict" "deploy/overlays/prod"

echo "PASS: environment selection test passed"
