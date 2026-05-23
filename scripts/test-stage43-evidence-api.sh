#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

db="$tmpdir/evidence-store.db"
reportdir="$tmpdir/reports"
release_id="20260101-000000"

mkdir -p "$reportdir"

cat > "$reportdir/release-evidence-${release_id}.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-stage43-evidence-api.sh",
  "releaseResult": "PASS",
  "policyDecision": "ALLOW",
  "finalAction": "NOOP",
  "executionMode": "advisory_only",
  "requiresHumanApproval": false,
  "safeToRetry": true,
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "summary": {
    "riskLevel": "low",
    "riskScore": 0
  },
  "artifacts": {}
}
JSON

cat > "$reportdir/signed-release-gate-${release_id}.json" <<JSON
{
  "schemaVersion": "signed.release.gate/v1alpha1",
  "signedReleaseGateId": "srg-${release_id}",
  "release": {
    "releaseId": "${release_id}",
    "service": "demo-app",
    "namespace": "slo-rollout",
    "env": "dev"
  },
  "verification": {
    "schemaVersion": "signed.release.gate.verification/v1alpha1",
    "mode": "input_derived",
    "tool": "cosign",
    "toolBinary": "cosign",
    "toolAvailable": false,
    "results": {
      "signatureVerified": false,
      "sbomPresent": true,
      "provenancePresent": true,
      "slsaLevelPresent": "unknown"
    },
    "guardrails": {
      "canRunExternalVerification": false,
      "doesNotRunExternalCommands": true
    }
  }
}
JSON

run_json() {
  local name="$1"
  shift

  echo "===== ${name} ====="
  "$@" | tee "$tmpdir/${name}.json"
}

assert_schema() {
  local name="$1"
  local expected="$2"

  "$PYTHON_BIN" - "$tmpdir/${name}.json" "$expected" <<'PY'
import json
import sys

path, expected = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

got = data.get("schemaVersion")
if got != expected:
    raise SystemExit(f"{path}: expected schemaVersion={expected}, got={got}")
PY
}

echo "===== python compile ====="
"$PYTHON_BIN" -m py_compile scripts/evidence-store.py

echo "===== watcher evidence service boundary ====="
(
  cd watcher
  go test ./...
)

grep -q "type EvidenceService" watcher/evidence_service.go
grep -q "type EvidenceRuntime" watcher/evidence_service.go
grep -q "type EvidenceRuntimeDescriptor" watcher/evidence_service.go
grep -q "cli-sqlite-runtime" watcher/evidence_service.go
grep -q "evidence.api.service/v1alpha1" watcher/evidence_service.go
grep -q "NewCLIEvidenceRepository" watcher/evidence_repository.go
grep -q "X-S-Sentinel-Evidence-Runtime-Mode" watcher/portal_api.go

if grep -q "runEvidenceStoreCommand" watcher/portal_api.go; then
  echo "portal_api.go still owns EvidenceStore CLI runtime"
  exit 1
fi

# Legacy CLI compatibility.
run_json init-db "$PYTHON_BIN" scripts/evidence-store.py init-db --db "$db"
assert_schema init-db evidence.store.init/v1alpha1

run_json import-dir "$PYTHON_BIN" scripts/evidence-store.py import-dir --db "$db" --report-dir "$reportdir"
assert_schema import-dir evidence.store.import/v1alpha1

run_json list-releases "$PYTHON_BIN" scripts/evidence-store.py list-releases --db "$db" --limit 10
assert_schema list-releases evidence.store.releaseList/v1alpha1

run_json query-release "$PYTHON_BIN" scripts/evidence-store.py query-release --db "$db" --release-id "$release_id"
assert_schema query-release evidence.store.release/v1alpha1

run_json get-object "$PYTHON_BIN" scripts/evidence-store.py get-object --db "$db" --object-type releaseEvidence --object-id "re-${release_id}" --release-id "$release_id"
assert_schema get-object evidence.store.object/v1alpha1

# Stage43 canonical/new CLI compatibility.
run_json schema "$PYTHON_BIN" scripts/evidence-store.py schema --db "$db"
assert_schema schema evidence.store.schema/v1alpha1

run_json list-artifacts "$PYTHON_BIN" scripts/evidence-store.py list-artifacts --db "$db" --release-id "$release_id"
assert_schema list-artifacts evidence.store.artifactList/v1alpha1

run_json search-objects "$PYTHON_BIN" scripts/evidence-store.py search-objects --db "$db" --query demo-app --limit 10
assert_schema search-objects evidence.store.search/v1alpha1

run_json verification-summary "$PYTHON_BIN" scripts/evidence-store.py verification-summary --db "$db" --release-id "$release_id"
assert_schema verification-summary evidence.store.verificationSummary/v1alpha1

run_json graph "$PYTHON_BIN" scripts/evidence-store.py graph --db "$db" --release-id "$release_id"
assert_schema graph evidence.store.graph/v1alpha1

echo "===== semantic assertions ====="
"$PYTHON_BIN" - "$tmpdir" "$release_id" <<'PY'
import json
import sys
from pathlib import Path

tmpdir = Path(sys.argv[1])
release_id = sys.argv[2]

def load(name):
    with open(tmpdir / f"{name}.json", encoding="utf-8") as f:
        return json.load(f)

import_result = load("import-dir")
if import_result.get("releaseCount") != 1:
    raise SystemExit(f"expected releaseCount=1, got {import_result}")
if import_result.get("importedObjects") != 2:
    raise SystemExit(f"expected importedObjects=2, got {import_result}")

release_list = load("list-releases")
if release_list.get("count", 0) < 1:
    raise SystemExit(f"expected at least one release, got {release_list}")

query_release = load("query-release")
if query_release.get("objectCount") != 2:
    raise SystemExit(f"expected objectCount=2, got {query_release}")

search = load("search-objects")
if search.get("count", 0) < 1:
    raise SystemExit(f"expected search count >= 1, got {search}")

verification = load("verification-summary")
latest = verification.get("latest") or {}
if latest.get("verificationMode") != "input_derived":
    raise SystemExit(f"expected verificationMode=input_derived, got {verification}")

expected_external_fields = {
    "externalVerificationRequested",
    "externalVerificationAllowed",
    "externalVerificationExecuted",
    "externalVerificationSucceeded",
    "externalVerificationSkippedReason",
}
missing_external_fields = sorted(field for field in expected_external_fields if field not in latest)
if missing_external_fields:
    raise SystemExit(f"verification summary missing external fields={missing_external_fields}, got {verification}")

graph = load("graph")
if graph.get("nodeCount", 0) < 3:
    raise SystemExit(f"expected graph nodeCount >= 3, got {graph}")
if graph.get("edgeCount", 0) < 2:
    raise SystemExit(f"expected graph edgeCount >= 2, got {graph}")

if graph.get("releaseId") != release_id:
    raise SystemExit(f"expected graph releaseId={release_id}, got {graph.get('releaseId')}")

print("stage43 evidence api compatibility assertions passed")
PY

echo "===== watcher API compatibility tests ====="
(
  cd watcher
  go test -run 'TestPortalEvidenceStoreAdapter|TestEvidenceStorePythonRuntimeEnvOverride' -v
)

echo "===== stage43 evidence api compatibility PASS ====="
