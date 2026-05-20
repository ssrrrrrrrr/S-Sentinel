#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE="$ROOT_DIR/tests/fixtures/release-contracts/release-evidence-fail-multiple-slo.json"

RCA_OUTPUT_DIR="$TMP_DIR" bash "$ROOT_DIR/scripts/build-release-rca.sh" "$FIXTURE"

OUT="$TMP_DIR/rca-fail-multiple-slo.md"

test -f "$OUT"
test -f "$TMP_DIR/rca-latest.md"

grep -q "# Release RCA" "$OUT"
grep -q "Incident Summary" "$OUT"
grep -q "FAIL_BY_MULTIPLE_SLO" "$OUT"
grep -q "STOP_PROMOTION" "$OUT"
grep -q "Root Cause Hypothesis" "$OUT"
grep -q "SLO Evidence" "$OUT"
grep -q "Follow-up Actions" "$OUT"
grep -q "Safety Notes" "$OUT"

echo "PASS release RCA generation"
