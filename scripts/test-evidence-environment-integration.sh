#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"

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

release_evidence="$(latest_file "$REPORT_DIR/release-evidence-*.json")"

if [ -z "$release_evidence" ] || [ ! -f "$release_evidence" ]; then
  echo "ERROR: no release evidence file found under $REPORT_DIR" >&2
  exit 1
fi

./scripts/build-evidence-record.sh "$release_evidence" >/tmp/slo-evidence-environment-record.log 2>&1
cat /tmp/slo-evidence-environment-record.log

evidence_record="$REPORT_DIR/evidence-record-$(basename "$release_evidence" | sed 's/^release-evidence-//')"

python3 - "$release_evidence" "$evidence_record" <<'PY'
import json
import sys
from pathlib import Path

evidence_path = Path(sys.argv[1])
record_path = Path(sys.argv[2])

assert evidence_path.is_file(), evidence_path
assert record_path.is_file(), record_path

evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
record = json.loads(record_path.read_text(encoding="utf-8"))

assert evidence["env"] == "dev", evidence
assert evidence["environmentConfigRef"] == "configs/environments/dev.yaml", evidence
assert evidence["environment"]["profile"] == "dev", evidence["environment"]
assert evidence["environment"]["clusterName"] == "local-dev", evidence["environment"]
assert evidence["environment"]["namespace"] == "slo-rollout", evidence["environment"]
assert evidence["environment"]["policyProfile"] == "dev-advisory", evidence["environment"]
assert evidence["environment"]["gitopsOverlayPath"] == "deploy/overlays/dev", evidence["environment"]
assert evidence["environment"]["configFound"] is True, evidence["environment"]
assert evidence["artifacts"]["environmentConfig"] == "configs/environments/dev.yaml", evidence["artifacts"]

assert record["env"] == "dev", record
assert record["environmentConfigRef"] == "configs/environments/dev.yaml", record
assert record["environmentProfile"] == "dev", record
assert record["clusterName"] == "local-dev", record
assert record["policyProfile"] == "dev-advisory", record
assert record["gitopsOverlayPath"] == "deploy/overlays/dev", record
assert record["environment"]["configCaptured"] is True, record["environment"]
assert record["links"]["environmentConfig"] == "configs/environments/dev.yaml", record["links"]
assert record["artifacts"]["environmentConfig"]["exists"] is True, record["artifacts"]["environmentConfig"]

print("PASS: evidence environment integration test passed")
PY
