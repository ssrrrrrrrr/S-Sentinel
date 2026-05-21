#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_TIMELINE_OUTPUT_DIR="${RELEASE_TIMELINE_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}" \
  "$SCRIPT_DIR/build-release-timeline.sh" "$RELEASE_EVIDENCE_FILE"

python3 - "$RELEASE_EVIDENCE_FILE" "$RELEASE_TIMELINE_OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
output_dir = Path(sys.argv[2])

release_id = evidence.name.removeprefix("release-evidence-").removesuffix(".json")
timeline = output_dir / f"release-timeline-{release_id}.json"
latest = output_dir / "release-timeline-latest.json"

if not timeline.exists():
    raise SystemExit(f"timeline not generated: {timeline}")

if not latest.exists():
    raise SystemExit(f"latest timeline not generated: {latest}")

doc = json.loads(timeline.read_text(encoding="utf-8"))

assert doc["schemaVersion"] == "release.timeline/v1alpha1"
assert doc["releaseId"] == release_id
assert isinstance(doc["events"], list) and len(doc["events"]) >= 8
assert "coverage" in doc
assert "safety" in doc and doc["safety"]["readOnly"] is True

stages = {event["stage"] for event in doc["events"]}
required = {
    "release_context_collected",
    "ai_decision_generated",
    "policy_decision_evaluated",
    "release_evidence_built",
    "action_plan_generated",
    "release_intelligence_generated",
    "runbook_generated",
    "rca_generated",
}

missing = sorted(required - stages)
if missing:
    raise SystemExit(f"timeline missing required stages: {missing}")

print("PASS release timeline:", timeline)
print("events:", len(doc["events"]))
print("coverage:", doc["coverage"])
PY
