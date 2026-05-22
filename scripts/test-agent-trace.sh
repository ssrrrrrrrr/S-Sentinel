#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="${TMP_DIR:-/tmp/ssentinel-agent-trace-test}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

AI_DECISION="$TMP_DIR/ai-decision-20260101-000000.json"
POLICY_DECISION="$TMP_DIR/policy-decision-20260101-000000.json"
POLICY_RUNTIME="$TMP_DIR/policy-runtime-result-20260101-000000.json"
SIGNED_GATE="$TMP_DIR/signed-release-gate-20260101-000000.json"
RELEASE_EVIDENCE="$TMP_DIR/release-evidence-20260101-000000.json"
AGENT_TRACE="$TMP_DIR/agent-trace-20260101-000000.json"

cat > "$AI_DECISION" <<'JSON'
{
  "schemaVersion": "ai.release.advisor/v1alpha1",
  "generatedBy": "test-agent-trace.sh",
  "generatedAt": "2026-01-01T00:00:00Z",
  "releaseId": "20260101-000000",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "recommendedAction": "STOP_PROMOTION",
  "requiresHumanApproval": true,
  "service": "demo-app",
  "env": "dev",
  "sloId": "demo-app-canary-slo",
  "strategyId": "demo-app-canary-strategy",
  "agentAction": {
    "type": "STOP_PROMOTION",
    "allowed": true,
    "requiresApproval": true
  },
  "evidence": {
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "env": "dev",
    "image": "registry.local/demo-app@sha256:111",
    "imageDigest": "sha256:111"
  },
  "sources": {
    "releaseContext": "/tmp/ssentinel-agent-trace-test/release-context-20260101-000000.json"
  }
}
JSON

cat > "$POLICY_DECISION" <<'JSON'
{
  "schemaVersion": "release.policy.evaluator/v1alpha1",
  "policyDecisionId": "pd-20260101-000000",
  "releaseId": "20260101-000000",
  "service": "demo-app",
  "env": "dev",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "requestedAction": "STOP_PROMOTION",
  "allowed": true,
  "finalAction": "STOP_PROMOTION",
  "requiresHumanApproval": true,
  "matchedRules": [
    "slo_failure_stop_promotion_allowed_by_strategy",
    "signed_release_gate_requires_human_approval"
  ],
  "signedReleaseGate": {
    "signedReleaseGateId": "srg-20260101-000000",
    "decision": "REQUIRE_HUMAN_APPROVAL"
  },
  "safety": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$POLICY_RUNTIME" <<'JSON'
{
  "schemaVersion": "policy.runtime.result/v1alpha1",
  "generatedBy": "test-agent-trace.sh",
  "generatedAt": "2026-01-01T00:00:01Z",
  "runtime": {
    "name": "local-python",
    "adapter": "evaluate-agent-decision.sh",
    "mode": "subprocess"
  },
  "policyInputRef": "/tmp/ssentinel-agent-trace-test/policy-input-20260101-000000.json",
  "policyDecision": {
    "policyDecisionId": "pd-20260101-000000",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "allowed": true,
    "requiresHumanApproval": true
  },
  "summary": {
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION",
    "allowed": true,
    "requiresHumanApproval": true,
    "matchedRules": [
      "signed_release_gate_requires_human_approval"
    ],
    "signedReleaseGateDecision": "REQUIRE_HUMAN_APPROVAL"
  },
  "safety": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$SIGNED_GATE" <<'JSON'
{
  "schemaVersion": "signed.release.gate/v1alpha1",
  "signedReleaseGateId": "srg-20260101-000000",
  "generatedBy": "test-agent-trace.sh",
  "generatedAt": "2026-01-01T00:00:02Z",
  "mode": "read_only_signed_release_gate",
  "release": {
    "releaseId": "20260101-000000",
    "service": "demo-app",
    "env": "dev"
  },
  "image": {
    "image": "registry.local/demo-app@sha256:111",
    "imageDigest": "sha256:111",
    "usesDigestReference": true
  },
  "decision": {
    "decision": "REQUIRE_HUMAN_APPROVAL",
    "allowed": false,
    "requiresHumanApproval": true,
    "blockingReasons": [],
    "warningReasons": [
      "Cosign signature is not verified"
    ]
  },
  "risk": {
    "riskLevel": "high",
    "riskScore": 50
  },
  "guardrails": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$RELEASE_EVIDENCE" <<'JSON'
{
  "schemaVersion": "release.evidence.bundle/v1alpha1",
  "generatedBy": "test-agent-trace.sh",
  "generatedAt": "2026-01-01T00:00:03Z",
  "releaseId": "20260101-000000",
  "service": "demo-app",
  "env": "dev",
  "releaseResult": "FAIL_BY_MULTIPLE_SLO",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "aiDecision": "/tmp/ssentinel-agent-trace-test/ai-decision-20260101-000000.json",
    "policyDecision": "/tmp/ssentinel-agent-trace-test/policy-decision-20260101-000000.json",
    "signedReleaseGate": "/tmp/ssentinel-agent-trace-test/signed-release-gate-20260101-000000.json"
  }
}
JSON

echo "===== build agent trace ====="
AGENT_TRACE_OUTPUT_DIR="$TMP_DIR" ./scripts/build-agent-trace.sh "$AI_DECISION"

cat "$AGENT_TRACE"

echo
echo "===== assert agent trace contract ====="
python3 - "$AGENT_TRACE" "$TMP_DIR/agent-trace-latest.json" schemas/agent-trace.schema.json <<'PY'
import json
import sys
from pathlib import Path

trace = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
latest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
schema = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))

assert schema["properties"]["schemaVersion"]["const"] == "agent.trace/v1alpha1", schema
assert trace["schemaVersion"] == "agent.trace/v1alpha1", trace
assert trace["agentTraceId"] == "at-20260101-000000", trace
assert trace["traceId"] == "trace-20260101-000000", trace
assert trace["releaseId"] == "20260101-000000", trace
assert trace["release"]["service"] == "demo-app", trace
assert trace["release"]["env"] == "dev", trace
assert trace["release"]["imageDigest"] == "sha256:111", trace

assert trace["correlation"]["releaseId"] == "20260101-000000", trace
assert trace["correlation"]["agentRunId"] == "ar-20260101-000000", trace
assert trace["correlation"]["policyDecisionId"] == "pd-20260101-000000", trace
assert trace["correlation"]["policyRuntimeResultId"] == "prr-20260101-000000", trace
assert trace["correlation"]["signedReleaseGateId"] == "srg-20260101-000000", trace

assert trace["agentRun"]["status"] == "COMPLETED", trace
assert trace["policyTrace"]["policyDecision"] == "REQUIRE_HUMAN_APPROVAL", trace
assert trace["policyTrace"]["finalAction"] == "STOP_PROMOTION", trace
assert trace["signedReleaseGateTrace"]["decision"] == "REQUIRE_HUMAN_APPROVAL", trace
assert trace["signedReleaseGateTrace"]["riskLevel"] == "high", trace

names = {item["name"] for item in trace["toolCallTraces"]}
assert "ai_release_advisor" in names, trace
assert "policy_runtime_adapter" in names, trace
assert "policy_guard" in names, trace
assert "signed_release_gate" in names, trace
assert "release_evidence" in names, trace

assert trace["evidenceTrace"]["aiDecision"].endswith("ai-decision-20260101-000000.json"), trace
assert trace["evidenceTrace"]["signedReleaseGate"].endswith("signed-release-gate-20260101-000000.json"), trace
assert trace["guardrails"]["readOnly"] is True, trace
assert trace["guardrails"]["willExecute"] is False, trace
assert latest["agentTraceId"] == trace["agentTraceId"], latest

print("PASS: agent trace contract is valid")
PY

echo
echo "===== assert agent trace EvidenceStore indexing ====="
DB_FILE="$TMP_DIR/evidence-store.db"
IMPORT_JSON="$TMP_DIR/evidence-store-import.json"
OBJECT_JSON="$TMP_DIR/agent-trace-object.json"

./scripts/evidence-store.py init-db --db "$DB_FILE" >/dev/null
./scripts/evidence-store.py import-dir --db "$DB_FILE" --report-dir "$TMP_DIR" > "$IMPORT_JSON"
./scripts/evidence-store.py get-object \
  --db "$DB_FILE" \
  --object-type agentTrace \
  --object-id at-20260101-000000 \
  --release-id 20260101-000000 \
  > "$OBJECT_JSON"

python3 - "$IMPORT_JSON" "$OBJECT_JSON" <<'PY_ASSERT_EVIDENCE_STORE'
import json
import sys
from pathlib import Path

import_result = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
obj = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

assert import_result["byType"]["agentTrace"] == 1, import_result
assert obj["schemaVersion"] == "evidence.store.object/v1alpha1", obj
assert obj["object"]["object_type"] == "agentTrace", obj
assert obj["object"]["object_id"] == "at-20260101-000000", obj
assert obj["object"]["schema_version"] == "agent.trace/v1alpha1", obj
assert obj["object"]["summary"]["objectType"] == "agentTrace", obj
assert obj["object"]["summary"]["schemaVersion"] == "agent.trace/v1alpha1", obj

print("PASS: agent trace is imported into EvidenceStore")
PY_ASSERT_EVIDENCE_STORE

echo
echo "===== assert ai-release-advisor agent trace integration ====="
grep -q 'AGENT_TRACE_BUILDER' scripts/ai-release-advisor.sh
grep -q 'build-agent-trace.sh' scripts/ai-release-advisor.sh
grep -q 'AGENT_TRACE_OUTPUT_DIR' scripts/ai-release-advisor.sh
grep -q 'Running agent trace builder' scripts/ai-release-advisor.sh
grep -q 'build-agent-trace.sh failed' scripts/ai-release-advisor.sh
grep -q '"object_type": "agentTrace"' scripts/evidence-store.py
grep -q 'agent.trace/v1alpha1' scripts/evidence-store.py
grep -q 'agent-trace-*.json' scripts/evidence-store.py
echo "PASS: ai-release-advisor agent trace integration is wired"

echo "PASS: agent trace test passed"
