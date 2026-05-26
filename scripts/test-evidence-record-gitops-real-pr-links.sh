#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_TMP=".tmp/test-evidence-record-gitops-real-pr-links"
rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

cat > "$TEST_TMP/release-evidence-20260526-230000.json" <<'JSON'
{
  "schemaVersion": "release.evidence/v1alpha1",
  "releaseId": "20260526-230000",
  "service": "demo-app",
  "env": "dev",
  "namespace": "slo-rollout",
  "version": "v-real-pr-evidence",
  "generatedAt": "2026-05-26T15:00:00Z",
  "generatedBy": "test-evidence-record-gitops-real-pr-links.sh",
  "releaseResult": "STOP_PROMOTION",
  "policyDecision": "REQUIRE_HUMAN_APPROVAL",
  "finalAction": "STOP_PROMOTION",
  "artifacts": {
    "gitopsRealPRCreate": "gitops-real-pr-create-20260526-230000.json",
    "gitopsRealPRCleanup": "gitops-real-pr-cleanup-20260526-230000.json"
  },
  "safety": {
    "readOnly": true,
    "willExecute": false
  }
}
JSON

cat > "$TEST_TMP/gitops-real-pr-create-20260526-230000.json" <<'JSON'
{
  "schemaVersion": "gitops.real.pr.create/v1alpha1",
  "gitopsRealPRCreateId": "gprcreate-20260526-230000",
  "release": {
    "releaseId": "20260526-230000",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "pullRequest": {
    "createStatus": "PULL_REQUEST_CREATED",
    "repo": "ssrrrrrrrr/S-Sentinel",
    "number": 7,
    "state": "OPEN",
    "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
    "headRefName": "ssentinel/evidence-record-real-pr-smoke",
    "baseRefName": "main",
    "mergeStateStatus": "CLEAN"
  },
  "guardrails": {
    "didCreatePullRequest": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  }
}
JSON

cat > "$TEST_TMP/gitops-real-pr-cleanup-20260526-230000.json" <<'JSON'
{
  "schemaVersion": "gitops.real.pr.cleanup/v1alpha1",
  "gitopsRealPRCleanupId": "gprcleanup-20260526-230000",
  "release": {
    "releaseId": "20260526-230000",
    "service": "demo-app",
    "env": "dev",
    "namespace": "slo-rollout",
    "policyDecision": "REQUIRE_HUMAN_APPROVAL",
    "finalAction": "STOP_PROMOTION"
  },
  "cleanup": {
    "cleanupStatus": "CLEANED_UP",
    "pullRequest": {
      "number": 7,
      "state": "CLOSED",
      "url": "https://github.com/ssrrrrrrrr/S-Sentinel/pull/7",
      "headRefName": "ssentinel/evidence-record-real-pr-smoke",
      "baseRefName": "main"
    },
    "remoteBranchExists": false,
    "remoteHeads": []
  },
  "guardrails": {
    "didClosePullRequest": true,
    "didDeleteRemoteBranch": true,
    "doesNotMergePullRequest": true,
    "doesNotModifyKubernetes": true
  }
}
JSON

echo "===== build evidence record ====="
EVIDENCE_RECORD_OUTPUT_DIR="$TEST_TMP" \
  scripts/build-evidence-record.sh "$TEST_TMP/release-evidence-20260526-230000.json" >/tmp/ssentinel-evidence-record-real-pr-build.log

cat /tmp/ssentinel-evidence-record-real-pr-build.log

RECORD="$TEST_TMP/evidence-record-20260526-230000.json"

echo "===== assert evidence record links ====="
python3 - "$RECORD" <<'PY'
import json
import sys
from pathlib import Path

record = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

assert record["schemaVersion"] == "evidence.record/v1alpha1", record
assert record["releaseId"] == "20260526-230000", record

links = record.get("links") or {}
artifacts = record.get("artifacts") or {}

assert links.get("gitopsRealPRCreate", "").endswith("gitops-real-pr-create-20260526-230000.json"), links
assert links.get("gitopsRealPRCleanup", "").endswith("gitops-real-pr-cleanup-20260526-230000.json"), links

assert artifacts["gitopsRealPRCreate"]["exists"] is True, artifacts.get("gitopsRealPRCreate")
assert artifacts["gitopsRealPRCleanup"]["exists"] is True, artifacts.get("gitopsRealPRCleanup")

print("PASS evidence-record gitops real-pr links")
PY
