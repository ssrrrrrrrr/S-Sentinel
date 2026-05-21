#!/usr/bin/env bash
set -euo pipefail

REPORT_DIR="${RELEASE_REPORT_DIR:-docs/release-reports}"
RELEASE_EVIDENCE_FILE="${1:-latest}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-evidence-record.sh [latest|RELEASE_EVIDENCE_JSON]

Environment:
  RELEASE_REPORT_DIR              Optional report directory.
  EVIDENCE_RECORD_OUTPUT_DIR      Optional output directory. Defaults to release evidence directory.

Behavior:
  - Reads release-evidence-*.json.
  - Generates evidence-record-<releaseId>.json and evidence-record-latest.json.
  - Builds a control-plane evidence index without executing Kubernetes, GitOps, rollback, promote, patch, or delete actions.
USAGE
}

if [ "$RELEASE_EVIDENCE_FILE" = "-h" ] || [ "$RELEASE_EVIDENCE_FILE" = "--help" ]; then
  usage
  exit 0
fi

if [ "$RELEASE_EVIDENCE_FILE" = "latest" ] || [ -z "$RELEASE_EVIDENCE_FILE" ]; then
  RELEASE_EVIDENCE_FILE="$(ls -t "$REPORT_DIR"/release-evidence-*.json 2>/dev/null | grep -v 'release-evidence-latest.json' | head -1 || true)"
fi

if [ -z "$RELEASE_EVIDENCE_FILE" ] || [ ! -f "$RELEASE_EVIDENCE_FILE" ]; then
  echo "ERROR: release evidence file does not exist: ${RELEASE_EVIDENCE_FILE:-not provided}" >&2
  exit 1
fi

OUTPUT_DIR="${EVIDENCE_RECORD_OUTPUT_DIR:-$(dirname "$RELEASE_EVIDENCE_FILE")}"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$RELEASE_EVIDENCE_FILE")"
SUFFIX="${BASENAME#release-evidence-}"

if [ "$SUFFIX" = "$BASENAME" ]; then
  SUFFIX="$(date +%Y%m%d-%H%M%S).json"
fi

OUTPUT_JSON="$OUTPUT_DIR/evidence-record-$SUFFIX"
LATEST_JSON="$OUTPUT_DIR/evidence-record-latest.json"

python3 - "$RELEASE_EVIDENCE_FILE" "$OUTPUT_JSON" "$LATEST_JSON" <<'PY'
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

evidence_path = Path(sys.argv[1])
output_json = Path(sys.argv[2])
latest_json = Path(sys.argv[3])

def now() -> str:
    return datetime.now(timezone.utc).isoformat()

def load_json(path: Path | None) -> dict[str, Any]:
    if not path:
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def scalar(value: Any, fallback: str = "unknown") -> str:
    if value is None:
        return fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list):
        return ",".join(scalar(item) for item in value) if value else "none"
    return str(value)

def nullable_string(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None

def release_id_from_evidence(path: Path) -> str:
    base = path.name
    if base.startswith("release-evidence-") and base.endswith(".json"):
        return base[len("release-evidence-"):-len(".json")]
    return path.stem

def resolve_ref(ref: Any, source_path: Path) -> Path | None:
    if not ref:
        return None

    ref_path = Path(str(ref))
    candidates = [ref_path]

    if not ref_path.is_absolute():
        candidates.extend([
            Path.cwd() / ref_path,
            source_path.parent / ref_path.name,
            source_path.parent / ref_path,
        ])

    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)

        try:
            if candidate.exists() and candidate.is_file():
                return candidate
        except OSError:
            continue

    return None

def file_modified_at(path: Path | None) -> str | None:
    if not path:
        return None
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()
    except OSError:
        return None

def file_size(path: Path | None) -> int | None:
    if not path:
        return None
    try:
        return path.stat().st_size
    except OSError:
        return None

def content_type(path: Path | None, kind: str) -> str | None:
    if not path:
        return None
    suffix = path.suffix.lower()
    if suffix == ".json":
        return "application/json"
    if suffix == ".md":
        return "text/markdown"
    if suffix in (".yaml", ".yml"):
        return "application/yaml"
    if kind:
        return "application/octet-stream"
    return None

def artifact_entry(kind: str, ref: Any, source_path: Path, required: bool = False) -> dict[str, Any]:
    resolved = resolve_ref(ref, source_path)
    return {
        "kind": kind,
        "path": str(resolved) if resolved else nullable_string(ref),
        "exists": resolved is not None,
        "required": required,
        "contentType": content_type(resolved, kind),
        "sizeBytes": file_size(resolved),
        "modifiedAt": file_modified_at(resolved),
    }

def objective_ids(snapshot: Any) -> list[str]:
    if not isinstance(snapshot, dict):
        return []
    spec = snapshot.get("spec") or {}
    objectives = spec.get("objectives") or []
    if not isinstance(objectives, list):
        return []
    ids: list[str] = []
    for item in objectives:
        if isinstance(item, dict) and item.get("id"):
            ids.append(str(item["id"]))
    return ids

evidence = load_json(evidence_path)
release_id = release_id_from_evidence(evidence_path)

artifacts = evidence.get("artifacts") if isinstance(evidence.get("artifacts"), dict) else {}
summary = evidence.get("summary") if isinstance(evidence.get("summary"), dict) else {}
decision_refs = evidence.get("decisionRefs") if isinstance(evidence.get("decisionRefs"), dict) else {}

release_context_path = resolve_ref(artifacts.get("releaseContext"), evidence_path)
release_context = load_json(release_context_path)

service = evidence.get("service") or release_context.get("service")
namespace = release_context.get("namespace")
env = evidence.get("env") or release_context.get("env")

version = (
    release_context.get("currentDesiredVersion")
    or release_context.get("version")
    or release_context.get("appVersion")
)

change_context = release_context.get("changeContext") if isinstance(release_context.get("changeContext"), dict) else {}
image_obj = change_context.get("image") if isinstance(change_context.get("image"), dict) else {}
image = image_obj.get("current") or image_obj.get("target") or image_obj.get("new") or image_obj.get("image")
commit = change_context.get("commit") or change_context.get("gitCommit")
image_digest = change_context.get("imageDigest") or image_obj.get("digest")

slo_snapshot = evidence.get("sloConfigSnapshot")
slo_id = evidence.get("sloId") or release_context.get("sloId")
slo_config_ref = evidence.get("sloConfigRef") or release_context.get("sloConfigRef")

link_map = {
    "releaseContext": artifacts.get("releaseContext"),
    "releaseEvidence": str(evidence_path),
    "aiDecision": artifacts.get("aiDecision"),
    "policyDecision": artifacts.get("policyDecision"),
    "actionPlan": artifacts.get("actionPlan"),
    "approval": artifacts.get("approvalRecord") or artifacts.get("approval"),
    "timeline": artifacts.get("releaseTimeline") or artifacts.get("timeline"),
    "runbook": artifacts.get("runbook"),
    "rca": artifacts.get("rca"),
}

artifact_defs = [
    ("releaseContext", link_map["releaseContext"], True),
    ("releaseEvidence", link_map["releaseEvidence"], True),
    ("releaseReport", artifacts.get("releaseReport"), False),
    ("aiAdvice", artifacts.get("aiAdvice"), False),
    ("aiDecision", link_map["aiDecision"], True),
    ("policyDecision", link_map["policyDecision"], True),
    ("releaseSummary", artifacts.get("releaseSummary"), False),
    ("failureEvidence", artifacts.get("failureEvidence"), False),
    ("failureEvidenceReport", artifacts.get("failureEvidenceReport"), False),
    ("actionPlan", link_map["actionPlan"], False),
    ("actionPlanReport", artifacts.get("actionPlanReport"), False),
    ("releaseIntelligence", artifacts.get("releaseIntelligence"), False),
    ("releaseIntelligenceReport", artifacts.get("releaseIntelligenceReport"), False),
    ("approval", link_map["approval"], False),
    ("timeline", link_map["timeline"], False),
    ("runbook", link_map["runbook"], False),
    ("rca", link_map["rca"], False),
]

artifact_records = {
    kind: artifact_entry(kind, ref, evidence_path, required)
    for kind, ref, required in artifact_defs
}

total = len(artifact_records)
collected = sum(1 for item in artifact_records.values() if item.get("exists"))
missing = [kind for kind, item in artifact_records.items() if not item.get("exists")]

safe_service = scalar(service, "unknown").replace("/", "-").replace(" ", "-")
safe_env = scalar(env, "unknown").replace("/", "-").replace(" ", "-")
evidence_id = f"ev-{release_id}-{safe_service}-{safe_env}"

record = {
    "schemaVersion": "evidence.record/v1alpha1",
    "generatedBy": "build-evidence-record.sh",
    "generatedAt": now(),
    "evidenceId": evidence_id,
    "releaseId": release_id,
    "service": service,
    "namespace": namespace,
    "env": env,
    "version": nullable_string(version),
    "commit": nullable_string(commit),
    "image": nullable_string(image),
    "imageDigest": nullable_string(image_digest),
    "sourceEvidence": str(evidence_path),
    "releaseResult": scalar(evidence.get("releaseResult")),
    "policyDecision": scalar(evidence.get("policyDecision")),
    "finalAction": scalar(evidence.get("finalAction")),
    "executionMode": nullable_string(evidence.get("executionMode")),
    "requiresHumanApproval": bool(evidence.get("requiresHumanApproval", False)),
    "slo": {
        "sloId": slo_id,
        "sloConfigRef": slo_config_ref,
        "snapshotCaptured": isinstance(slo_snapshot, dict),
        "objectiveIds": objective_ids(slo_snapshot),
    },
    "summary": summary,
    "artifacts": artifact_records,
    "links": {
        key: nullable_string(value)
        for key, value in link_map.items()
    },
    "decisionRefs": decision_refs,
    "coverage": {
        "total": total,
        "collected": collected,
        "missing": missing,
    },
    "safety": {
        "readOnly": True,
        "willExecute": False,
        "supportsRollback": False,
        "supportsPromote": False,
        "supportsPatch": False,
        "supportsDelete": False,
    },
}

output_json.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
shutil.copyfile(output_json, latest_json)

print(f"Evidence record generated: {output_json}")
print(f"Latest evidence record: {latest_json}")
print(json.dumps({
    "evidenceId": evidence_id,
    "releaseId": release_id,
    "service": service,
    "env": env,
    "releaseResult": record["releaseResult"],
    "policyDecision": record["policyDecision"],
    "collected": collected,
    "total": total,
    "missing": missing,
}, indent=2, ensure_ascii=False))
PY
