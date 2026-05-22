#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -z "${PYTHON_BIN:-}" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "ERROR: python runtime not found. Set PYTHON_BIN=/path/to/python." >&2
    exit 1
  fi
fi

export PYTHON_BIN
export S_SENTINEL_PYTHON_BIN="${S_SENTINEL_PYTHON_BIN:-$PYTHON_BIN}"

section() {
  echo
  echo "===== $* ====="
}

section "Stage 42 platform hardening runtime context"
echo "ROOT_DIR=$ROOT_DIR"
echo "PYTHON_BIN=$PYTHON_BIN"
echo "S_SENTINEL_PYTHON_BIN=$S_SENTINEL_PYTHON_BIN"
"$PYTHON_BIN" --version

section "Stage 42 shell syntax checks"
bash -n scripts/test-evidence-store.sh
bash -n scripts/test-stage37-evidence-store.sh
bash -n scripts/test-stage38-policy-runtime-adapter.sh
bash -n scripts/test-stage39-signed-release-gate.sh
bash -n scripts/validate-release-portal-api.sh
bash -n scripts/validate-generated-release-contract.sh
bash -n scripts/validate-slo-config.sh
bash -n scripts/validate-progressive-delivery-strategy.sh
echo "PASS: shell syntax checks passed"

section "Stage 42 Go adapter runtime regression"
(
  cd watcher
  S_SENTINEL_PYTHON_BIN="$S_SENTINEL_PYTHON_BIN" go test ./... -count=1
)
echo "PASS: Go EvidenceStore adapter runtime regression passed"

section "Stage 42 config validator default resolver regression"
(
  unset PYTHON_BIN
  bash scripts/validate-slo-config.sh
  bash scripts/validate-progressive-delivery-strategy.sh
)
echo "PASS: config validators default resolver passed"

section "Stage 42 config validator explicit PYTHON_BIN regression"
PYTHON_BIN="$PYTHON_BIN" bash scripts/validate-slo-config.sh
PYTHON_BIN="$PYTHON_BIN" bash scripts/validate-progressive-delivery-strategy.sh
echo "PASS: config validators explicit PYTHON_BIN passed"

section "Stage 42 EvidenceStore CLI runtime regression"
(
  unset PYTHON_BIN
  bash scripts/test-evidence-store.sh > /tmp/s-sentinel-stage42-evidence-store-default.log
)
PYTHON_BIN="$PYTHON_BIN" bash scripts/test-evidence-store.sh > /tmp/s-sentinel-stage42-evidence-store-explicit.log

grep -q "PASS: evidence store test passed" /tmp/s-sentinel-stage42-evidence-store-default.log
grep -q "PASS: evidence store test passed" /tmp/s-sentinel-stage42-evidence-store-explicit.log
echo "PASS: EvidenceStore default and explicit runtime regressions passed"

section "Stage 42 Stage 37 runtime acceptance"
PYTHON_BIN="$PYTHON_BIN" bash scripts/test-stage37-evidence-store.sh
echo "PASS: Stage 37 EvidenceStore acceptance passed under Stage 42 runtime boundary"

section "Stage 42 Stage 38 runtime acceptance"
PYTHON_BIN="$PYTHON_BIN" bash scripts/test-stage38-policy-runtime-adapter.sh
echo "PASS: Stage 38 Policy Runtime Adapter acceptance passed under Stage 42 runtime boundary"

if [ "${RUN_STAGE39:-0}" = "1" ]; then
  section "Stage 42 optional Stage 39 runtime acceptance"
  PYTHON_BIN="$PYTHON_BIN" bash scripts/test-stage39-signed-release-gate.sh
  echo "PASS: optional Stage 39 Signed Release Gate acceptance passed"
else
  section "Stage 42 optional Stage 39 runtime acceptance skipped"
  echo "Set RUN_STAGE39=1 to include Stage 39 full regression."
fi

section "Stage 42 broken resolver guard"
if grep -RIn '"\$PYTHON_BIN" -m pip\|"\$PYTHON_BIN"-yaml\|"\$PYTHON_BIN"-jsonschema' \
  scripts/test-stage37-evidence-store.sh \
  scripts/test-evidence-store.sh \
  scripts/test-stage38-policy-runtime-adapter.sh \
  scripts/test-stage39-signed-release-gate.sh \
  scripts/validate-release-portal-api.sh \
  scripts/validate-generated-release-contract.sh \
  scripts/validate-slo-config.sh \
  scripts/validate-progressive-delivery-strategy.sh; then
  echo "FAIL: broken PYTHON_BIN string interpolation pattern found" >&2
  exit 1
fi

if grep -RIn 'if command -v "\$PYTHON_BIN" >/dev/null 2>&1; then' \
  scripts/test-stage37-evidence-store.sh \
  scripts/test-evidence-store.sh \
  scripts/test-stage38-policy-runtime-adapter.sh \
  scripts/test-stage39-signed-release-gate.sh \
  scripts/validate-release-portal-api.sh \
  scripts/validate-slo-config.sh \
  scripts/validate-progressive-delivery-strategy.sh; then
  echo "FAIL: broken PYTHON_BIN resolver pattern found" >&2
  exit 1
fi

echo "PASS: no broken PYTHON_BIN resolver patterns found"

section "Stage 42 platform hardening acceptance result"
echo "PASS: Stage 42 platform hardening runtime acceptance passed"
