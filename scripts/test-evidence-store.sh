#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-evidence-store-test}"
FIXTURE_DIR="$TMP_DIR/reports"
DB_FILE="$TMP_DIR/evidence-store.db"
QUERY_JSON="$TMP_DIR/query-release.json"
RELEASE_ID="20260101-000000"

rm -rf "$TMP_DIR"
mkdir -p "$FIXTURE_DIR"

cat > "$FIXTURE_DIR/release-evidence-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:00Z",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "policyDecisionId": "pd-$RELEASE_ID",
  "executionMode": "advisory_only",
  "requiresHumanApproval": true,
  "safeToRetry": false,
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "summary": {
    "riskLevel": "critical",
    "riskScore": 100,
    "failedMetrics": ["error-rate", "p95-latency"]
  },
  "artifacts": {
    "releaseContext": "release-context-$RELEASE_ID.json",
    "agentRun": "agent-run-$RELEASE_ID.json",
    "planRun": "plan-run-$RELEASE_ID.json",
    "executionRequest": "execution-request-$RELEASE_ID.json",
    "supplyChainDecision": "supply-chain-decision-$RELEASE_ID.json"
  },
  "agentRunId": "ar-$RELEASE_ID",
  "planRunId": "pr-$RELEASE_ID",
  "executionRequestId": "er-$RELEASE_ID",
  "supplyChainDecisionId": "sc-$RELEASE_ID"
}
JSON

cat > "$FIXTURE_DIR/evidence-record-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "evidence.record/v1alpha1",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:01Z",
  "evidenceId": "ev-$RELEASE_ID-demo-app-dev",
  "releaseId": "$RELEASE_ID",
  "service": "demo-app",
  "namespace": "slo-rollout",
  "env": "dev",
  "sourceEvidence": "release-evidence-$RELEASE_ID.json",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "requiresHumanApproval": true,
  "summary": {
    "riskLevel": "critical",
    "riskScore": 100
  },
  "artifacts": {
    "releaseEvidence": {
      "kind": "releaseEvidence",
      "path": "release-evidence-$RELEASE_ID.json",
      "exists": true
    }
  },
  "links": {
    "releaseEvidence": "release-evidence-$RELEASE_ID.json"
  }
}
JSON

cat > "$FIXTURE_DIR/agent-run-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "agent.run/v1alpha1",
  "agentRunId": "ar-$RELEASE_ID",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:02Z",
  "mode": "read_only",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO"
  },
  "recommendation": {
    "recommendedAction": "STOP_PROMOTION",
    "priority": "critical",
    "willExecute": false
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$FIXTURE_DIR/plan-run-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "agent.plan.run/v1alpha1",
  "planRunId": "pr-$RELEASE_ID",
  "sourceAgentRunId": "ar-$RELEASE_ID",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:03Z",
  "mode": "read_only_planning",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "recommendedAction": "STOP_PROMOTION"
  },
  "plan": {
    "planType": "rag_assisted_failure_investigation",
    "priority": "critical",
    "willExecute": false
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$FIXTURE_DIR/execution-request-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "execution.request/v1alpha1",
  "executionRequestId": "er-$RELEASE_ID",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:04Z",
  "mode": "request_only",
  "sourcePlanRunId": "pr-$RELEASE_ID",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL"
  },
  "request": {
    "requestedAction": "STOP_PROMOTION",
    "requestStatus": "PENDING_APPROVAL",
    "willExecute": false
  },
  "policyBinding": {
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "requiresHumanApproval": true,
    "willExecute": false
  },
  "guardrails": {
    "requestOnly": true,
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$FIXTURE_DIR/supply-chain-decision-$RELEASE_ID.json" <<JSON
{
  "schemaVersion": "supply.chain.decision/v1alpha1",
  "supplyChainDecisionId": "sc-$RELEASE_ID",
  "generatedBy": "test-evidence-store.sh",
  "generatedAt": "2026-01-01T00:00:05Z",
  "mode": "read_only_supply_chain_check",
  "release": {
    "releaseId": "$RELEASE_ID",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "releaseResult": "FAIL_BY_MULTIPLE_SLO"
  },
  "image": {
    "image": "192.168.30.11:30500/sre/demo-app:v-test",
    "imageTag": "v-test",
    "imageDigest": null
  },
  "decision": {
    "decision": "REQUIRE_HUMAN_APPROVAL",
    "requiresHumanApproval": true,
    "allowed": true
  },
  "risk": {
    "riskLevel": "high",
    "riskScore": 70
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

echo "===== init db ====="
./scripts/evidence-store.py init-db --db "$DB_FILE"

echo
echo "===== import fixture dir ====="
./scripts/evidence-store.py import-dir --db "$DB_FILE" --report-dir "$FIXTURE_DIR"

echo
echo "===== query release ====="
./scripts/evidence-store.py query-release --db "$DB_FILE" --release-id "$RELEASE_ID" > "$QUERY_JSON"
cat "$QUERY_JSON"

echo
echo "===== assert query result ====="
python3 - "$QUERY_JSON" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
release = data["release"]
objects = data["objects"]
kinds = {item["object_type"] for item in objects}
expected = {
    "releaseEvidence",
    "evidenceRecord",
    "agentRun",
    "planRun",
    "executionRequest",
    "supplyChainDecision",
}

assert release["release_id"] == "20260101-000000", release
assert release["service"] == "demo-app", release
assert release["env"] == "dev", release
assert release["release_result"] == "FAIL_BY_MULTIPLE_SLO", release
assert release["policy_decision"] == "REQUIRE_HUMAN_APPROVAL", release
assert release["final_action"] == "STOP_PROMOTION", release
assert expected.issubset(kinds), kinds
assert data["objectCount"] == 6, data["objectCount"]
assert data["artifactCount"] >= 1, data["artifactCount"]

ids = {item["object_type"]: item["object_id"] for item in objects}
assert ids["evidenceRecord"].startswith("ev-")
assert ids["agentRun"].startswith("ar-")
assert ids["planRun"].startswith("pr-")
assert ids["executionRequest"].startswith("er-")
assert ids["supplyChainDecision"].startswith("sc-")

print("PASS: EvidenceStore query result is valid")
PY

echo
echo "PASS: evidence store test passed"
