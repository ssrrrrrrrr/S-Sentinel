#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-docs/release-reports}"
mkdir -p "$OUTPUT_DIR"

RELEASE_ID="${S_SENTINEL_RELEASE_ID:-runtime-inspect-smoke}"
SERVICE="${S_SENTINEL_SERVICE:-demo-app}"
ENVIRONMENT="${S_SENTINEL_ENV:-dev}"
NAMESPACE="${S_SENTINEL_NAMESPACE:-slo-rollout}"
ROLLOUT_NAME="${S_SENTINEL_ROLLOUT_NAME:-demo-app}"

python3 - "$OUTPUT_DIR" "$RELEASE_ID" "$SERVICE" "$ENVIRONMENT" "$NAMESPACE" "$ROLLOUT_NAME" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

output_dir = Path(sys.argv[1])
release_id = sys.argv[2]
service = sys.argv[3]
env = sys.argv[4]
namespace = sys.argv[5]
rollout_name = sys.argv[6]

generated_at = datetime.now(timezone.utc).isoformat()

doc = {
    "schemaVersion": "runtime.rollout.inspect/v1alpha1",
    "rolloutRuntimeInspectId": "rti-" + release_id,
    "generatedBy": "build-rollout-runtime-inspect.sh",
    "generatedAt": generated_at,
    "mode": "fixture_rollout_runtime_inspect",
    "release": {
        "releaseId": release_id,
        "service": service,
        "env": env,
        "namespace": namespace,
        "policyDecision": "REQUIRE_HUMAN_APPROVAL",
        "finalAction": "STOP_PROMOTION",
    },
    "target": {
        "cluster": "local-dev",
        "namespace": namespace,
        "rolloutName": rollout_name,
        "service": service,
        "env": env,
    },
    "rollout": {
        "name": rollout_name,
        "namespace": namespace,
        "phase": "Progressing",
        "strategy": "Canary",
        "currentStepIndex": 2,
        "replicas": 3,
        "updatedReplicas": 1,
        "readyReplicas": 3,
        "availableReplicas": 3,
        "desiredWeight": 20,
        "actualWeight": 20,
        "paused": False,
        "degraded": False,
        "message": "Fixture rollout inspect snapshot; no Kubernetes command executed.",
    },
    "analysis": {
        "analysisRunName": "demo-app-analysis-" + release_id,
        "status": "Running",
        "successful": 0,
        "failed": 0,
        "inconclusive": 0,
    },
    "guardrails": {
        "readOnly": True,
        "dryRunOnly": True,
        "willExecute": False,
        "doesNotPause": True,
        "doesNotResume": True,
        "doesNotPromote": True,
        "doesNotAbort": True,
        "doesNotRollback": True,
        "doesNotModifyKubernetes": True,
    },
}

output = output_dir / f"rollout-runtime-inspect-{release_id}.json"
latest = output_dir / "rollout-runtime-inspect-latest.json"

text = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
output.write_text(text, encoding="utf-8")
latest.write_text(text, encoding="utf-8")

print(output)
PY
