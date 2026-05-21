#!/usr/bin/env bash
set -euo pipefail

TEST_TMP="${1:-/tmp/slo-stage34-multi-env-packaging-test}"

rm -rf "$TEST_TMP"
mkdir -p "$TEST_TMP"

log() {
  echo
  echo "===== $* ====="
}

log "Stage 34.1 environment config contract"
./scripts/test-environment-config.sh

log "Stage 34.2 GitOps packaging boundary"
./scripts/test-packaging-boundary.sh

log "Stage 34.3 evidence environment integration"
./scripts/test-evidence-environment-integration.sh

log "Stage 34.4 runtime environment selection"
./scripts/test-environment-selection.sh "$TEST_TMP/environment-selection"

log "STAGE 34 MULTI-ENV PACKAGING TESTS PASSED"
