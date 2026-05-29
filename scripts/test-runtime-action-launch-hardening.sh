#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

run() {
  echo
  echo "===== $* ====="
  "$@"
}

echo "===== S Sentinel runtime action launch hardening acceptance ====="
echo "scope=mock_and_fixture_only"
echo "doesNotModifyKubernetes=true"
echo "doesNotModifyGitOps=true"

run bash -c 'python3 -m json.tool schemas/runtime-action-execution-result.schema.json >/dev/null'
run bash -c 'python3 -m json.tool schemas/evidence-record.schema.json >/dev/null'
run python3 -m py_compile scripts/evidence-store.py

run bash scripts/test-runtime-action-execution-result.sh
run bash scripts/test-runtime-action-execution-result-canonical-summaries.sh
run bash scripts/test-runtime-action-execution-result-execution-summary.sh
run bash scripts/test-runtime-action-execution-result-gate-summary.sh
run bash scripts/test-runtime-action-execution-result-verification-summary.sh
run bash scripts/test-runtime-action-execution-result-risk-summary.sh

run bash scripts/test-runtime-action-execution-result-mock-pause.sh
run bash scripts/test-runtime-action-execution-result-mock-resume.sh
run bash scripts/test-runtime-action-execution-result-mock-promote.sh
run bash scripts/test-runtime-action-execution-result-mock-abort.sh
run bash scripts/test-runtime-action-execution-result-mock-rollback.sh

run bash scripts/test-evidence-record-runtime-action-execution-result-links.sh
run bash scripts/test-evidence-record-runtime-action-execution-result-resume-links.sh
run bash scripts/test-evidence-record-runtime-action-execution-result-promote-links.sh
run bash scripts/test-evidence-record-runtime-action-execution-result-abort-links.sh
run bash scripts/test-evidence-record-runtime-action-execution-result-rollback-links.sh

run bash scripts/test-evidence-store-runtime-action-execution-result.sh
run bash scripts/test-evidence-store-runtime-action-execution-result-resume.sh
run bash scripts/test-evidence-store-runtime-action-execution-result-promote.sh
run bash scripts/test-evidence-store-runtime-action-execution-result-abort.sh
run bash scripts/test-evidence-store-runtime-action-execution-result-rollback.sh

echo
echo "PASS runtime action launch hardening acceptance"
