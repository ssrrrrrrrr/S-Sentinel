#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE="$ROOT_DIR/tests/fixtures/release-contracts/release-evidence-fail-multiple-slo.json"

RUNBOOK_OUTPUT_DIR="$TMP_DIR" bash "$ROOT_DIR/scripts/build-release-runbook.sh" "$FIXTURE"

OUT="$TMP_DIR/runbook-fail-multiple-slo.md"

test -f "$OUT"
test -f "$TMP_DIR/runbook-latest.md"

grep -q "# Release Runbook" "$OUT"
grep -q "FAIL_BY_MULTIPLE_SLO" "$OUT"
grep -q "STOP_PROMOTION" "$OUT"
grep -q "Human Checklist" "$OUT"
grep -q "Command Reference" "$OUT"
grep -q "Safety Statement" "$OUT"

echo "PASS release runbook generation"
